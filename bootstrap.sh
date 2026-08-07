#!/bin/bash
# Dotfiles bootstrap — platform-aware orchestrator
set -euo pipefail

DOTFILES="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# --- Platform detection ------------------------------------------------------
# Reported only — bootstrap remains a linker, not a provisioner. NixOS and WSL
# are detected so later sections (and the user) can adapt.
_DOT_PLATFORM_NIXOS=0
_DOT_PLATFORM_WSL=0
if [[ -f /etc/os-release ]] && grep -qi '^ID=nixos' /etc/os-release 2> /dev/null; then
  _DOT_PLATFORM_NIXOS=1
fi
if [[ -f /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version 2> /dev/null; then
  _DOT_PLATFORM_WSL=1
fi

# Resolve the runtime/lock directory once, consistently. Honors XDG_RUNTIME_HOME
# (set by systemd/NixOS) and requires it to be writable; falls back to /tmp.
# Mirrors scripts/verify-migration.sh.
_dotfiles_lock_dir() {
  if [[ -n "${XDG_RUNTIME_HOME:-}" && -w "${XDG_RUNTIME_HOME:-}" ]]; then
    printf '%s/.dotfiles\n' "$XDG_RUNTIME_HOME"
  else
    printf '/tmp\n'
  fi
}

_dotfiles_lock() {
  local _lock_dir lockfile
  _lock_dir="$(_dotfiles_lock_dir)"
  mkdir -p "$_lock_dir" 2> /dev/null || true
  lockfile="$_lock_dir/.dotfiles-bootstrap.lock"
  if ! (
    set -o noclobber
    : > "$lockfile"
  ) 2> /dev/null; then
    echo "ERROR: another bootstrap may be running ($lockfile exists)" >&2
    exit 1
  fi
  echo "$$" > "$lockfile"
}

_dotfiles_unlock() {
  local _lock_dir lockfile
  _lock_dir="$(_dotfiles_lock_dir)"
  lockfile="$_lock_dir/.dotfiles-bootstrap.lock"
  rm -f "$lockfile" 2> /dev/null || true
}

_dotfiles_lock
trap _dotfiles_unlock EXIT

echo "Bootstrapping dotfiles..."
if [[ $_DOT_PLATFORM_NIXOS -eq 1 ]]; then echo "  nixos:  yes"; else echo "  nixos:  no"; fi
if [[ $_DOT_PLATFORM_WSL -eq 1 ]]; then echo "  wsl:    yes"; else echo "  wsl:    no"; fi
echo "  distro:  $(uname -sr)"
echo "  dotfiles: $DOTFILES"
echo

BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
_backup_used=0

backup_and_link() {
  local source="$1" target="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      local current
      current="$(readlink "$target")"
      if [[ "$current" == "$source" ]]; then
        echo "already linked: $target"
        return 0
      fi
    fi
    [[ $_backup_used -eq 0 ]] && mkdir -p "$BACKUP_DIR"
    _backup_used=1
    echo "backing up: $target"
    if ! mv "$target" "$BACKUP_DIR/"; then
      echo "ERROR: failed to move $target to $BACKUP_DIR" >&2
      exit 1
    fi
  fi
  echo "linking: $target -> $source"
  if ! ln -s "$source" "$target"; then
    echo "ERROR: failed to link $target -> $source" >&2
    exit 1
  fi
}

backup_and_link "$DOTFILES/.profile" "$HOME/.profile"
backup_and_link "$DOTFILES/.bash_profile" "$HOME/.bash_profile"
backup_and_link "$DOTFILES/.bashrc" "$HOME/.bashrc"
backup_and_link "$DOTFILES/.zprofile" "$HOME/.zprofile"
backup_and_link "$DOTFILES/.zshrc" "$HOME/.zshrc"
backup_and_link "$DOTFILES/.gitconfig" "$HOME/.gitconfig"
backup_and_link "$DOTFILES/.gitignore_global" "$HOME/.gitignore_global"
backup_and_link "$DOTFILES/.forward" "$HOME/.forward"

# Directory scaffolding. mkdir is tolerant: on NixOS a Home Manager-managed
# $HOME may own e.g. .config and be read-only, and on WSL interop mounts
# POSIX perms may be absent. Never abort the whole bootstrap over a
# non-critical directory.
_ensure_dir() { mkdir -p "$@" 2> /dev/null || true; }

_ensure_dir "$HOME/bin" "$HOME/.local/bin"
_ensure_dir "$HOME/.gnupg" "$HOME/.ssh"
_ensure_dir "$HOME/.config/vim" "$HOME/.config/npm"

# GPG/SSH dirs must stay private. On some interop mounts (WSL against NTFS
# without the `metadata` flag) chmod is a no-op — tolerate that instead of
# dying under `set -e` (consistent with the guarded chmods below).
chmod 700 "$HOME/.gnupg" "$HOME/.ssh" 2> /dev/null || true

for bin_file in "$DOTFILES/bin/"*; do
  [[ -f "$bin_file" ]] || continue
  backup_and_link "$bin_file" "$HOME/bin/$(basename "$bin_file")"
done

backup_and_link "$DOTFILES/.config/gpg/gpg.conf" "$HOME/.gnupg/gpg.conf"
backup_and_link "$DOTFILES/.config/gpg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
chmod 600 "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf" 2> /dev/null || true
backup_and_link "$DOTFILES/.vimrc" "$HOME/.vimrc"
backup_and_link "$DOTFILES/.config/ssh/config" "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config" 2> /dev/null || true

# WSL: symlink Windows-host SSH keys so headless git/SSH works without manual
# key management. Robust to:
#   * cmd.exe not in PATH (NixOS WSL disables interop by default) — falls back
#     to the Unix $USER/LOGNAME.
#   * Windows on a non-C: drive — enumerates /mnt/<letter>/Users.
#   * Windows username differing from the Unix username.
if [[ $_DOT_PLATFORM_WSL -eq 1 ]]; then
  _wsl_winuser="${USER:-${LOGNAME:-}}"
  if command -v cmd.exe > /dev/null 2>&1; then
    _wsl_winuser="$(cmd.exe /c 'echo %USERNAME%' 2> /dev/null | tr -d '\r\n')"
    _wsl_winuser="${_wsl_winuser:-${USER:-${LOGNAME:-}}}"
  fi
  _wsl_key_src=""
  for _drive in /mnt/[a-z]; do
    [[ -d "$_drive" ]] || continue
    _wsl_candidate="$_drive/Users/${_wsl_winuser}/.ssh/id_ed25519"
    if [[ -f "$_wsl_candidate" && -f "$_wsl_candidate.pub" ]]; then
      _wsl_key_src="$_wsl_candidate"
      break
    fi
  done
  if [[ -n "$_wsl_key_src" ]]; then
    _wsl_key_pub="${_wsl_key_src}.pub"
    if [[ ! -e "$HOME/.ssh/id_ed25519" ]]; then
      ln -s "$_wsl_key_src" "$HOME/.ssh/id_ed25519"
      echo "linked: $HOME/.ssh/id_ed25519 -> $_wsl_key_src"
    elif [[ -L "$HOME/.ssh/id_ed25519" ]]; then
      ln -sf "$_wsl_key_src" "$HOME/.ssh/id_ed25519"
      echo "relinked: $HOME/.ssh/id_ed25519 -> $_wsl_key_src"
    else
      echo "WARN: $HOME/.ssh/id_ed25519 exists but is not a symlink; leaving as-is"
    fi
    [[ ! -e "$HOME/.ssh/id_ed25519.pub" ]] && ln -s "$_wsl_key_pub" "$HOME/.ssh/id_ed25519.pub"
    # Do NOT chmod the Windows-host key: NTFS (and drvfs without the `metadata`
    # mount option) does not persist POSIX permission bits, so chmod would be a
    # misleading no-op (or unexpectedly rewrite an ACL on the cross-mounted file).
    # Keep the key private via Windows ACLs instead.
  else
    echo "note: no Windows-side SSH key found under /mnt/*/Users/${_wsl_winuser}/.ssh (skipped WSL key link)"
  fi
  unset _wsl_winuser _drive _wsl_candidate _wsl_key_src _wsl_key_pub
fi
backup_and_link "$DOTFILES/.config/vim/vimrc" "$HOME/.config/vim/vimrc"
backup_and_link "$DOTFILES/.config/vim/privacy.vim" "$HOME/.config/vim/privacy.vim"
backup_and_link "$DOTFILES/.config/npm/config" "$HOME/.config/npm/config"
backup_and_link "$DOTFILES/.config/env.d" "$HOME/.config/env.d"

if [[ -d "$DOTFILES/.githooks" ]]; then
  git -C "$DOTFILES" config core.hooksPath .githooks
fi

if [[ "${DOTFILES_ENABLE_FISH:-0}" = "1" && -d "$DOTFILES/.config/fish" ]]; then
  mkdir -p "$HOME/.config/fish/conf.d"
  for fish_file in "$DOTFILES/.config/fish/conf.d/"*; do
    [[ -f "$fish_file" ]] || continue
    backup_and_link "$fish_file" "$HOME/.config/fish/conf.d/$(basename "$fish_file")"
  done
  echo "Fish config linked (DOTFILES_ENABLE_FISH=1)"
fi

if [[ "${DOTFILES_ENABLE_GH:-0}" = "1" && -f "$DOTFILES/.config/gh/config.yml" ]]; then
  mkdir -p "$HOME/.config/gh"
  # Link only config.yml (prefs). hosts.yml holds OAuth tokens — never tracked.
  backup_and_link "$DOTFILES/.config/gh/config.yml" "$HOME/.config/gh/config.yml"
  echo "gh config linked (DOTFILES_ENABLE_GH=1; hosts.yml untouched)"
fi

echo "Dotfiles bootstrapped successfully!"
[[ $_backup_used -eq 1 ]] && echo "Backup: $BACKUP_DIR"
echo "Restart your shell or run: source ~/.bashrc (bash) or source ~/.zshrc (zsh)"

if [[ ! -f "$HOME/.bashrc.local" ]]; then
  echo "Create ~/.bashrc.local for personal bash settings"
fi
if [[ ! -f "$HOME/.zshrc.local" ]]; then
  echo "Create ~/.zshrc.local for personal zsh settings"
fi
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
  echo "Create ~/.gitconfig.local with your git user info"
fi
if [[ ! -f "$HOME/.forward.local" ]]; then
  echo "Create ~/.forward.local for private mail forwarding"
fi

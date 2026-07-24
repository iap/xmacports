#!/bin/bash
# Dotfiles bootstrap — platform-aware orchestrator
set -euo pipefail

DOTFILES="${DOTFILES_ROOT:-$HOME/.dotfiles}"

_dotfiles_lock() {
  local lockfile="/tmp/.dotfiles-bootstrap.lock"
  if ! (set -o noclobber; : > "$lockfile") 2>/dev/null; then
    echo "ERROR: another bootstrap may be running ($lockfile exists)" >&2
    exit 1
  fi
  echo "$$" > "$lockfile"
}

_dotfiles_unlock() {
  rm -f "/tmp/.dotfiles-bootstrap.lock" 2>/dev/null || true
}

_dotfiles_lock
trap _dotfiles_unlock EXIT

echo "Bootstrapping dotfiles..."

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
    [[ $_backup_used -eq 0 ]] && mkdir -p "$BACKUP_DIR" && _backup_used=1
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

mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/.gnupg" "$HOME/.ssh" "$HOME/.config/vim" "$HOME/.config/npm"
chmod 700 "$HOME/.gnupg" "$HOME/.ssh"

for bin_file in "$DOTFILES/bin/"*; do
  [[ -f "$bin_file" ]] || continue
  backup_and_link "$bin_file" "$HOME/bin/$(basename "$bin_file")"
done

backup_and_link "$DOTFILES/.config/gpg/gpg.conf" "$HOME/.gnupg/gpg.conf"
backup_and_link "$DOTFILES/.config/gpg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
chmod 600 "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null || true
backup_and_link "$DOTFILES/.vimrc" "$HOME/.vimrc"
backup_and_link "$DOTFILES/.config/ssh/config" "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
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

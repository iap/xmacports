#!/bin/zsh
# ZSH Profile - shell entrypoint

if [[ -f "$HOME/.profile" ]]; then
  source "$HOME/.profile"
fi

# Load Shared modules (platform is the single source of truth; the rest are
# functions, secrets, prompt, aliases). All carry their own load guards.
# .profile normally sets DOTFILES_ROOT, but default it here too: zsh sources
# .zshrc directly for interactive non-login shells, where .profile never ran.
: "${DOTFILES_ROOT:=$HOME/.dotfiles}"
for _config_file in "$DOTFILES_ROOT/shared/"*.sh; do
  [[ -f "$_config_file" ]] && source "$_config_file"
done
unset _config_file

# Load per-host environment overrides from XDG config. Mirrors .bashrc so both
# shells get the same env.d modules — previously bash-only, which silently left
# foundry/proxy/user-local-bin inactive under zsh.
if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/env.d" ]]; then
  for _config_file in "${XDG_CONFIG_HOME:-$HOME/.config}"/env.d/*.sh; do
    [[ -f "$_config_file" ]] && source "$_config_file"
  done
  unset _config_file
fi

# Load zsh-specific drop-ins. Documented in AGENTS.md/MANUAL.md as the zsh
# extension point, but nothing sourced it — .zshrc.d/prompt.sh was dead code.
# Modules carry their own load guards, so this stays idempotent.
if [[ -d "$DOTFILES_ROOT/.zshrc.d" ]]; then
  for _config_file in "$DOTFILES_ROOT/.zshrc.d/"*.sh; do
    [[ -f "$_config_file" ]] && source "$_config_file"
  done
  unset _config_file
fi

# Load local profile customizations AFTER platform PATH setup
# This ensures user PATH additions in .profile.local get proper precedence
if [ -z "${DOTFILES_PROFILE_LOCAL_LOADED:-}" ] && [ -f "$HOME/.profile.local" ]; then
  source "$HOME/.profile.local"
  export DOTFILES_PROFILE_LOCAL_LOADED=1
fi

# History
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
[[ -d "$(dirname "$HISTFILE")" ]] || { mkdir -p "$(dirname "$HISTFILE")" && chmod 700 "$(dirname "$HISTFILE")"; }

# ZSH options
setopt AUTO_CD
setopt NO_NOMATCH # Pass unmatched globs through (fixes bare https:// URLs)
setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_VERIFY
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt CORRECT
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt PROMPT_SUBST
unsetopt BEEP
unsetopt FLOW_CONTROL

# Completion
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}"
compinit -C -d "$_zcompdump"
unset _zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# GPG/SSH attention: surface a wrong GPG_TTY in non-TTY sessions.
# NOTE: ssh-add -l only LISTS keys already in the agent; it does NOT
# load or unlock anything. For a real TTY unlock, trigger a signing op,
# e.g. `ssh -T git@gitlab.com`, which caches the passphrase 300s.
# For headless/CI use the dedicated ~/.ssh/id_ed25519 key (no TTY needed).
if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "${SSH_AUTH_SOCK:-}" ]] && has_cmd ssh-add; then
  # Warn (not silently background) if GPG_TTY is a bogus device in a non-TTY shell.
  if [[ ! -t 0 ]] && [[ "${GPG_TTY:-}" == "/dev/tty" ]]; then
    echo "[dotfiles] warning: GPG_TTY=/dev/tty but no TTY — pinentry will fail. Unset it for headless use." >&2
  fi
fi

# GPG verification (non-blocking)
if [[ -n "${DOTFILES_LOG_DIR:-}" ]] && declare -f verify_gpg_ssh > /dev/null; then
  if mkdir -p "$DOTFILES_LOG_DIR" 2> /dev/null && [[ -w "$DOTFILES_LOG_DIR" ]]; then
    verify_gpg_ssh > "$DOTFILES_LOG_DIR/gpg-verify.log" 2>&1 &
    disown
  fi
fi

# Optional developer tool manager.
# If `mise` exists, activate its shims; otherwise continue silently.
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)" 2> /dev/null || true
fi

# Local overrides
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Periodic dotfiles upstream check (fail-silent, throttled ~30 min)
_dc="/home/iap/.dotfiles/scripts/dotfiles-check.sh"
[ -x "" ] && "" || true
unset _dc

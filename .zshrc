#!/bin/zsh
# ZSH Profile - shell entrypoint

if [[ -f "$HOME/.profile" ]]; then
  source "$HOME/.profile"
fi

if [[ -f "$HOME/.dotfiles/.zshrc.d/env.sh" ]]; then
  source "$HOME/.dotfiles/.zshrc.d/env.sh"
fi

# Foundry wrappers (consistent with bash)
if [[ -f "$HOME/.dotfiles/.config/env.d/foundry.sh" ]]; then
  source "$HOME/.dotfiles/.config/env.d/foundry.sh"
fi

for _config_file in "$HOME/.dotfiles/shared/"*.sh; do
  [[ -f "$_config_file" ]] && source "$_config_file"
done
unset _config_file

for _config_file in "$HOME/.dotfiles/.zshrc.d/"*.sh; do
  [[ "$(basename "$_config_file")" == "env.sh" ]] && continue
  [[ -f "$_config_file" ]] && source "$_config_file"
done
unset _config_file

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

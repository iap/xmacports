#!/bin/bash

# History
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%s "
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
mkdir -p "$(dirname "$HISTFILE")"
shopt -s histappend

# Shell Options
shopt -s autocd 2> /dev/null
shopt -s globstar 2> /dev/null
shopt -s checkwinsize 2> /dev/null

# Load Cargo environment (interactive shells only)
if [ -z "${CARGO_HOME:-}" ] && [ -f "$HOME/.cargo/env" ] && [ -r "$HOME/.cargo/env" ]; then
  case ":${PATH}:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) . "$HOME/.cargo/env" ;;
  esac
fi

# Load Shared Functions
for f in functions.sh aliases.sh; do
  [[ -f "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/$f" ]] && source "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/$f"
done

# Optional developer tool manager.
# If `mise` exists, activate its shims; otherwise continue silently.
if has_cmd mise 2> /dev/null; then eval "$(mise activate bash)" 2> /dev/null || true; fi

# Load local profile customizations AFTER platform PATH setup
# This ensures user PATH additions in .profile.local get proper precedence
if [ -z "${DOTFILES_PROFILE_LOCAL_LOADED:-}" ] && [ -f "$HOME/.profile.local" ]; then
  source "$HOME/.profile.local"
  export DOTFILES_PROFILE_LOCAL_LOADED=1
fi

# Prompt — unified module shared with zsh
[[ -f "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/prompt.sh" ]] && source "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/prompt.sh"

# Local Overrides
[[ -f "$HOME/.bashrc.local" ]] && source "$HOME/.bashrc.local"

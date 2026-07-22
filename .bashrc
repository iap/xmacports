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
  [[ -f "$HOME/.dotfiles/shared/$f" ]] && source "$HOME/.dotfiles/shared/$f"
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


# Load per-host environment overrides from XDG config when this file is sourced
# directly, e.g. interactive bash without a login shell.
if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/env.d" ]]; then
  for _config_file in "${XDG_CONFIG_HOME:-$HOME/.config}"/env.d/*.sh; do
    [[ -f "$_config_file" ]] && source "$_config_file"
  done
  unset _config_file
fi
# Prompt — unified module shared with zsh
[[ -f "$HOME/.dotfiles/shared/prompt.sh" ]] && source "$HOME/.dotfiles/shared/prompt.sh"

# Local Overrides
[[ -f "$HOME/.bashrc.local" ]] && source "$HOME/.bashrc.local"

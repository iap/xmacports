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

# Load platform detection and environment (sets DOTFILES_ROOT, XDG vars, PATH)
DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
if [[ -f "$DOTFILES_ROOT/shared/platform.sh" ]]; then
  source "$DOTFILES_ROOT/shared/platform.sh"
fi

# Load Shared Functions (which also sources platform.sh, but guarded)
for f in functions.sh aliases.sh; do
  [[ -f "$DOTFILES_ROOT/shared/$f" ]] && source "$DOTFILES_ROOT/shared/$f"
done

# Optional developer tool manager.
# If `mise` exists, activate its shims; otherwise continue silently.
if has_cmd mise 2> /dev/null; then eval "$(mise activate bash)" 2> /dev/null || true; fi

# Load per-host environment overrides from XDG config when this file is sourced
# directly, e.g. interactive bash without a login shell.
if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/env.d" ]]; then
  for _config_file in "${XDG_CONFIG_HOME:-$HOME/.config}"/env.d/*.sh; do
    [[ -f "$_config_file" ]] && source "$_config_file"
  done
  unset _config_file
fi

# Prompt — unified module shared with zsh
[[ -f "$DOTFILES_ROOT/shared/prompt.sh" ]] && source "$DOTFILES_ROOT/shared/prompt.sh"

# Local Overrides
[[ -f "$HOME/.bashrc.local" ]] && source "$HOME/.bashrc.local"

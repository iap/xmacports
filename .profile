#!/bin/sh
# Central base configuration for all shells

if [ -n "${DOTFILES_PROFILE_LOADED:-}" ]; then
  return 0 2> /dev/null || exit 0
fi
export DOTFILES_PROFILE_LOADED=1

# XDG Base Directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# DOTFILES_ROOT: where this repo lives. Defaults to ~/.dotfiles.
# Override in ~/.profile.local if your checkout is elsewhere.
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

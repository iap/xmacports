#!/bin/sh
# POSIX-compatible base profile for all login shells
# Loaded by both bash (.bash_profile -> .profile) and zsh (.zprofile -> .profile)

# XDG Base Directory defaults (POSIX-compliant)
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME

# DOTFILES_ROOT - single source of truth for dotfiles repo location
# Can be overridden via environment variable before sourcing
: "${DOTFILES_ROOT:=$HOME/.dotfiles}"
export DOTFILES_ROOT

# Default editor (can be overridden in .profile.local)
: "${EDITOR:=vi}"
: "${VISUAL:=${EDITOR:-vi}}"
export EDITOR VISUAL

# Locale defaults (can be overridden by system)
: "${LANG:=en_US.UTF-8}"
: "${LC_ALL:=${LANG}}"
export LANG LC_ALL

# Load per-host overrides if they exist (after XDG setup).
# Set the guard so .bashrc/.zshrc do not source it a SECOND time — double
# sourcing re-prepends any PATH additions made there, defeating path_dedupe
# (which has already run by then) and leaving duplicate PATH entries.
if [ -z "${DOTFILES_PROFILE_LOCAL_LOADED:-}" ] && [ -f "$HOME/.profile.local" ]; then
  . "$HOME/.profile.local"
  DOTFILES_PROFILE_LOCAL_LOADED=1
  export DOTFILES_PROFILE_LOCAL_LOADED
fi

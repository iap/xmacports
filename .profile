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

# Load local profile customizations (for server overrides)
if [ -f "$HOME/.profile.local" ]; then
  . "$HOME/.profile.local"
fi

# Load Cargo environment (only if exists and not in restricted env)
if [ -z "$CARGO_HOME" ] && [ -f "$HOME/.cargo/env" ] && [ -r "$HOME/.cargo/env" ]; then
  # Check if we're on a shared/restricted host
  if command -v quota > /dev/null 2>&1; then
    # Likely shared host - skip cargo env
    :
  else
    . "$HOME/.cargo/env"
  fi
fi

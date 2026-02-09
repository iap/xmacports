#!/bin/sh
# Central base configuration for all shells
# Required by system rules - loaded by all POSIX-compliant shells

# Source centralized environment if available (only if not already loaded)
if [ -z "$DOTFILES_ENV_LOADED" ] && [ -f "$HOME/.dotfiles/.config/env.d/default.sh" ]; then
    . "$HOME/.dotfiles/.config/env.d/default.sh"
fi

# Load local profile customizations
if [ -f "$HOME/.profile.local" ]; then
    . "$HOME/.profile.local"
fi

# Load Cargo environment (only if not already loaded and exists)
if [ -z "$CARGO_HOME" ] && [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

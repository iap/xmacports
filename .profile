#!/bin/sh
# Central base configuration for all shells
# Required by system rules - loaded by all POSIX-compliant shells

# Source centralized environment if available.
# default.sh uses bash/zsh features, so only source it from compatible shells.
if [ -f "$HOME/.dotfiles/.config/env.d/default.sh" ]; then
    if [ -n "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
        . "$HOME/.dotfiles/.config/env.d/default.sh"
    fi
fi

# Load local profile customizations
if [ -f "$HOME/.profile.local" ]; then
    . "$HOME/.profile.local"
fi

# Load Cargo environment (only if not already loaded and exists)
if [ -z "$CARGO_HOME" ] && [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

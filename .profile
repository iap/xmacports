#!/bin/sh
# Central base configuration for all shells
# Required by system rules - loaded by all POSIX-compliant shells

# Source centralized environment if available
if [ -f "$HOME/.dotfiles/.config/env.d/default.sh" ]; then
    . "$HOME/.dotfiles/.config/env.d/default.sh"
fi

# Load local profile customizations
if [ -f "$HOME/.profile.local" ]; then
    . "$HOME/.profile.local"
fi
. "$HOME/.cargo/env"

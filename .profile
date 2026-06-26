#!/bin/sh
# Central base configuration for all shells

# Load local profile customizations (for server overrides)
if [ -f "$HOME/.profile.local" ]; then
    . "$HOME/.profile.local"
fi

# Load Cargo environment (only if exists and not in restricted env)
if [ -z "$CARGO_HOME" ] && [ -f "$HOME/.cargo/env" ] && [ -r "$HOME/.cargo/env" ]; then
    # Check if we're on a shared/restricted host
    if command -v quota >/dev/null 2>&1; then
        # Likely shared host - skip cargo env
        :
    else
        . "$HOME/.cargo/env"
    fi
fi
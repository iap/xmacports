#!/bin/bash
# Foundry wrappers

# Define wrapper function for all platforms
_with_foundry_libs() {
    local cmd="${1:-}"
    shift
    if [[ -d "$HOME/.foundry/lib" ]]; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # macOS: use DYLD_FALLBACK_LIBRARY_PATH
            (DYLD_FALLBACK_LIBRARY_PATH="$HOME/.foundry/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}" command "$cmd" "$@")
        else
            # Linux: use LD_LIBRARY_PATH
            (LD_LIBRARY_PATH="$HOME/.foundry/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" command "$cmd" "$@")
        fi
    else
        command "$cmd" "$@"
    fi
}

# Only proceed if Foundry tools are available
if [[ -d "$HOME/.foundry/bin" ]] && [[ -r "$HOME/.foundry/bin" ]]; then
    # Add to PATH only if not already there
    case ":$PATH:" in
        *":$HOME/.foundry/bin:"*) ;;
        *) export PATH="$HOME/.foundry/bin:$PATH" ;;
    esac
fi

# Foundry functions - work with or without foundry installed
forge() { _with_foundry_libs forge "$@"; }
cast() { _with_foundry_libs cast "$@"; }
anvil() { _with_foundry_libs anvil "$@"; }

#!/bin/bash
# Foundry wrappers

# Load platform detection (provides is_macos, has_cmd, FOUNDRY_BIN_PATH)
if [[ -f "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/platform.sh" ]]; then
  source "${DOTFILES_ROOT:-$HOME/.dotfiles}/shared/platform.sh"
fi

# Define wrapper function for all platforms
_with_foundry_libs() {
  local cmd="${1:-}"
  shift
  if [[ -d "$HOME/.foundry/lib" ]]; then
    if is_macos; then
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

# Only proceed if Foundry tools are available via FOUNDRY_BIN_PATH
if [[ -n "${FOUNDRY_BIN_PATH:-}" ]] && [[ -d "$FOUNDRY_BIN_PATH" ]] && [[ -r "$FOUNDRY_BIN_PATH" ]]; then
  # Add to PATH only if not already there
  case ":$PATH:" in
    *":$FOUNDRY_BIN_PATH:"*) ;;
    *) export PATH="$FOUNDRY_BIN_PATH:$PATH" ;;
  esac
fi

# Foundry functions - work with or without foundry installed
forge() { _with_foundry_libs forge "$@"; }
cast() { _with_foundry_libs cast "$@"; }
anvil() { _with_foundry_libs anvil "$@"; }

#!/bin/bash
# Platform-environment configuration — thin wrapper sourcing the unified platform.sh

set -u

# Load guard — respect DOTFILES_PLATFORM_LOADED from unified platform.sh
if [[ -n "${DOTFILES_PLATFORM_LOADED:-}" ]]; then
  return 0
fi

# Source the single source of truth
if [[ -f "$HOME/.dotfiles/shared/platform.sh" ]]; then
  source "$HOME/.dotfiles/shared/platform.sh"
fi

#!/bin/bash
# Platform-environment configuration — thin wrapper sourcing the unified platform.sh

set -u

# Source the single source of truth
if [[ -f "$HOME/.dotfiles/shared/platform.sh" ]]; then
  source "$HOME/.dotfiles/shared/platform.sh"
fi

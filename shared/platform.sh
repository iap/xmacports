#!/bin/bash
# Platform detection — single source of truth for OS/command checks.
# Intended to be sourced from bash or zsh.

# Use a non-exported guard to avoid leaking to child processes
if [[ -n "${DOTFILES_PLATFORM_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_PLATFORM_LOADED=1

set -u

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" > /dev/null 2>&1; }

# DOTFILES_ROOT defaults to ~/.dotfiles if not already set.
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

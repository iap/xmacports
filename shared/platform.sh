#!/bin/bash
# Platform detection — single source of truth for OS/command checks.
# Intended to be sourced from bash or zsh.

set -u

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" > /dev/null 2>&1; }

# DOTFILES_ROOT defaults to ~/.dotfiles if not already set.
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

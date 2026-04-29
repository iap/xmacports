#!/bin/bash
# Foundry wrappers to scope DYLD_LIBRARY_PATH (macOS/MacPorts).
# Shared by Bash and Zsh.

_with_foundry_libs() {
  if [ -x "$HOME/.dotfiles/bin/with-foundry-libs" ]; then
    "$HOME/.dotfiles/bin/with-foundry-libs" "$@"
  else
    "$@"
  fi
}

forge() { _with_foundry_libs command forge "$@"; }
cast() { _with_foundry_libs command cast "$@"; }
anvil() { _with_foundry_libs command anvil "$@"; }

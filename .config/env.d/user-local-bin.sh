#!/bin/sh
# Ensure user-local bins are available in shells that do not inherit a login profile.

if [ -n "${DOTFILES_USER_LOCAL_BIN_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
export DOTFILES_USER_LOCAL_BIN_LOADED=1

case ":${PATH:-}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) export PATH="${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${HOME}/bin:${PATH:-}" ;;
esac

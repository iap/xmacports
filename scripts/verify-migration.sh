#!/bin/bash
set -euo pipefail

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
TARGET="${1:-$HOME}"

_LOCK_DIR=""
if [ -n "${XDG_RUNTIME_HOME:-}" ] && [ -w "${XDG_RUNTIME_HOME:-}" ]; then
  _LOCK_DIR="${XDG_RUNTIME_HOME}/.dotfiles"
else
  _LOCK_DIR="/tmp"
fi
_LOCKFILE="${_LOCK_DIR}/.dotfiles-verify.lock"

mkdir -p "$_LOCK_DIR" 2>/dev/null || true
if ! (set -o noclobber; : > "$_LOCKFILE") 2>/dev/null; then
  echo "WARN: verify already running ($_LOCKFILE exists)" >&2
  exit 0
fi
trap 'rm -f "$_LOCKFILE" 2>/dev/null || true' EXIT

echo "[1/3] Checking DOTFILES_ROOT=$DOTFILES_ROOT"
if [ ! -d "$DOTFILES_ROOT" ]; then
  echo "MISSING: $DOTFILES_ROOT"
  exit 1
fi
if [ ! -r "$DOTFILES_ROOT/.bashrc" ] || [ ! -r "$DOTFILES_ROOT/.profile" ]; then
  echo "MISSING dotfiles config in $DOTFILES_ROOT"
  exit 1
fi

echo "[2/3] Checking symlink targets under $TARGET"
find -L "$TARGET" -maxdepth 1 -type l 2>/dev/null | while IFS= read -r link; do
  target="$(readlink "$link" 2>/dev/null || true)"
  if [ -n "$target" ] && [ "$target" != "$DOTFILES"/* ]; then
    echo "MISMATCH: $link -> $target"
  fi
done | sort -u || true

echo "[3/3] Runtime path checks"
for path in "$HOME/.gnupg" "$HOME/.ssh" "$HOME/.config"; do
  if [ ! -d "$path" ]; then
    echo "MISSING dir: $path"
  fi
done

echo "Migration verification complete"
exit 0

#!/bin/bash
# Run shellcheck

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

shell_for() {
  case "$1" in
    bin/pinentry-fallback) echo sh ;;
    *) echo bash ;;
  esac
}

while IFS= read -r -d '' f; do
  shellcheck -s "$(shell_for "$f")" "$f"
done < <(find . -type f \( \
  -name '*.sh' -o \
  -name '*.bash' -o \
  -name '*.zsh' -o \
  -name '.bashrc' -o \
  -name '.bash_profile' -o \
  -name '.profile' -o \
  -name '.zprofile' -o \
  -name '.zshrc' \
  \) -not -path './.git/*' -not -path './.kilo/*' -not -path './node_modules/*' -print0)

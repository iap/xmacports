#!/bin/bash
# Run shfmt

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mode="write"
[ "${1:-}" = "--check" ] && mode="check"

while IFS= read -r -d '' f; do
  if [ "$mode" = "check" ]; then
    shfmt -i 2 -ci -sr -d "$f"
  else
    shfmt -i 2 -ci -sr -w "$f"
  fi
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

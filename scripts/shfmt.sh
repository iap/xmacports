#!/bin/bash
# Run shfmt.
#
# Usage: scripts/shfmt.sh [--check] [--staged]
#   --check   verify formatting instead of rewriting
#   --staged  only staged (added/copied/modified) shell files — used by the
#             pre-commit hook so a commit doesn't pay for a full-repo scan

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mode="write"
STAGED=0
for _arg in "$@"; do
  case "$_arg" in
    --check) mode="check" ;;
    --staged) STAGED=1 ;;
    *)
      echo "unknown option: $_arg" >&2
      exit 2
      ;;
  esac
done

emit_full_repo() {
  find . -type f \( \
    -name '*.sh' -o \
    -name '*.bash' -o \
    -name '*.zsh' -o \
    -name '.bashrc' -o \
    -name '.bash_profile' -o \
    -name '.profile' -o \
    -name '.zprofile' -o \
    -name '.zshrc' -o \
    -path './bin/*' -o \
    -path './.githooks/*' \
    \) -not -path './.git/*' -not -path './.kilo/*' -not -path './node_modules/*' -print0
}

# Same predicate as emit_full_repo, applied to staged paths. git prints paths
# without the ./ prefix, and bash case avoids grep -z (BSD grep's -z is a
# different flag than GNU's null-data mode).
emit_staged() {
  while IFS= read -r -d '' f; do
    case "$f" in
      .git/* | .kilo/* | node_modules/* | */node_modules/*) continue ;;
      *.sh | *.bash | *.zsh | bin/* | .githooks/*) printf '%s\0' "$f" ;;
      */.bashrc | */.bash_profile | */.profile | */.zprofile | */.zshrc | .bashrc | .bash_profile | .profile | .zprofile | .zshrc) printf '%s\0' "$f" ;;
    esac
  done < <(git diff --cached --name-only --diff-filter=ACM -z)
}

if [ "$STAGED" = "1" ]; then
  src=emit_staged
else
  src=emit_full_repo
fi

while IFS= read -r -d '' f; do
  if [ "$mode" = "check" ]; then
    shfmt -i 2 -ci -sr -d "$f"
  else
    shfmt -i 2 -ci -sr -w "$f"
  fi
done < <("$src")

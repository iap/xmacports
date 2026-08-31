#!/bin/bash
# Run shellcheck.
#
# Usage: scripts/shellcheck.sh [--staged]
#   (default)  lint every shell file in the repo (CI / make shellcheck)
#   --staged   lint only staged (added/copied/modified) shell files — used by
#              the pre-commit hook so a commit doesn't pay for a full-repo scan

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STAGED=0
for _arg in "$@"; do
  case "$_arg" in
    --staged) STAGED=1 ;;
    *)
      echo "unknown option: $_arg" >&2
      exit 2
      ;;
  esac
done

shell_for() {
  case "$1" in
    bin/pinentry-fallback | ./bin/pinentry-fallback) echo sh ;;
    .githooks/* | ./.githooks/*) echo sh ;;
    # tests/test-zsh.zsh is intentionally a zsh script (shebang #!/usr/bin/env
    # zsh); shellcheck's bash mode errors on it (SC1071). It is linted under
    # zsh's own syntax when run by `make test-zsh`/CI's zsh lane, so skip it here.
    tests/test-zsh.zsh | ./tests/test-zsh.zsh) echo skip ;;
    *) echo bash ;;
  esac
}

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
  _shell="$(shell_for "$f")"
  [ "$_shell" = "skip" ] && continue
  shellcheck -s "$_shell" "$f"
done < <("$src")

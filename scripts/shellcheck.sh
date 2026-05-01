#!/bin/bash
# Run shellcheck on project shell scripts.

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

files=(
  "bootstrap.sh"
  "shared/functions.sh"
  "shared/aliases.sh"
  "bin/pinentry-fallback"
  "bin/system-info"
  "bin/update"
  "bin/with-foundry-libs"
  "scripts/benchmark.sh"
  "scripts/cleanup-zsh.sh"
  "scripts/cleanup-7d.sh"
  "scripts/compliance-check.sh"
  "scripts/install-cleanup-job.sh"
  "scripts/uninstall-cleanup-job.sh"
  "scripts/timeout_prompt.sh"
  "tests/run-tests.sh"
  "tests/test-functions.sh"
)

shell_for() {
  case "$1" in
    bin/pinentry-fallback | bin/with-foundry-libs)
      echo sh
      ;;
    *)
      echo bash
      ;;
  esac
}

for f in "${files[@]}"; do
  if [ -f "$f" ]; then
    shellcheck -s "$(shell_for "$f")" "$f"
  fi
done

#!/bin/bash
# Run shellcheck

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

files=(
  ".bash_profile"
  ".bashrc"
  "bootstrap.sh"
  ".config/env.d/foundry.sh"
  ".config/env.d/platform.sh"
  ".profile"
  ".zprofile"
  ".zshrc"
  ".zshrc.d/env.sh"
  ".zshrc.d/prompt.sh"
  "shared/functions.sh"
  "shared/aliases.sh"
  "bin/pinentry-fallback"
  "bin/system-info"
  "bin/update"
  "scripts/bootstrap-macos.sh"
  "scripts/benchmark.sh"
  "scripts/cleanup-zsh.sh"
  "scripts/cleanup-7d.sh"
  "scripts/compliance-check.sh"
  "scripts/install-cleanup-job.sh"
  "scripts/uninstall-cleanup-job.sh"
  "tests/run-tests.sh"
  "tests/test-functions.sh"
  "tests/verify-dotfiles.sh"
)

shell_for() {
  case "$1" in
    bin/pinentry-fallback)
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

#!/bin/bash
# Run shfmt - uses shared file manifest

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

files=(
  .bash_profile .bashrc bootstrap.sh
  .config/env.d/foundry.sh .config/env.d/platform.sh
  .profile .zprofile .zshrc
  .zshrc.d/env.sh .zshrc.d/prompt.sh
  bin/pinentry-fallback bin/system-info bin/update
  shared/aliases.sh shared/functions.sh
  scripts/audit.sh scripts/benchmark.sh scripts/bootstrap-macos.sh
  scripts/cleanup-7d.sh scripts/cleanup-zsh.sh scripts/compliance-check.sh
  scripts/install-cleanup-job.sh scripts/shfmt.sh scripts/shellcheck.sh
  scripts/uninstall-cleanup-job.sh
  tests/run-tests.sh tests/test-functions.sh tests/verify-dotfiles.sh
)

mode="write"
[ "${1:-}" = "--check" ] && mode="check"

if [ "$mode" = "check" ]; then
  shfmt -i 2 -ci -sr -d "${files[@]}"
else
  shfmt -i 2 -ci -sr -w "${files[@]}"
fi

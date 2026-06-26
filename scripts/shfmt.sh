#!/bin/bash
# Run shfmt

set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mode="write"
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
fi

files=(
  "bootstrap.sh"
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
  "scripts/shellcheck.sh"
  "scripts/shfmt.sh"
  "tests/run-tests.sh"
  "tests/test-functions.sh"
  "tests/verify-dotfiles.sh"
)

args=(
  -i 2
  -ci
  -sr
)

if [[ "$mode" == "check" ]]; then
  shfmt "${args[@]}" -d "${files[@]}"
else
  shfmt "${args[@]}" -w "${files[@]}"
fi

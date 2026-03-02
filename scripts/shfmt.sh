#!/bin/bash
# Run shfmt on project shell scripts.

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mode="write"
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
fi

files=(
  "bootstrap.sh"
  "bin/pinentry-fallback"
  "bin/system-info"
  "bin/update"
  "bin/with-foundry-libs"
  "scripts/benchmark.sh"
  "scripts/cleanup-zsh.sh"
  "scripts/compliance-check.sh"
  "scripts/shellcheck.sh"
  "scripts/shfmt.sh"
  "scripts/timeout_prompt.sh"
  "tests/run-tests.sh"
  "tests/test-functions.sh"
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

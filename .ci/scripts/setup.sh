#!/bin/sh
set -eu

# Install common dependencies for CI steps.
# Adapted from scripts/ci-setup.sh for GitLab CI (Alpine-based).
apk add --no-cache bash git python3 py3-yaml zsh make curl ca-certificates coreutils

# Install SAST-specific tools when requested.
if [ "${1:-}" = "sast" ]; then
  apk add --no-cache shellcheck shfmt
  # ruff powers `make python-lint`. Without it that gate silently skips in CI
  # and scripts/*.py ship unlinted. Installed from Alpine's repo rather than
  # via `uv tool run` so the CI image needs no network install at lint time.
  apk add --no-cache ruff
fi

#!/bin/sh
set -eu

# Install common dependencies for CI steps.
# Adapted from scripts/ci-setup.sh for GitLab CI (Alpine-based).
apk add --no-cache bash git python3 py3-yaml zsh make curl ca-certificates coreutils

# Install SAST-specific tools when requested.
if [ "${1:-}" = "sast" ]; then
  apk add --no-cache shellcheck shfmt
  # Install uv via official installer (not in Alpine repos).
  # uv provides 'uv tool run ruff' which the Makefile's python-lint target uses.
  curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --quiet
  export PATH="$HOME/.local/bin:$PATH"
fi

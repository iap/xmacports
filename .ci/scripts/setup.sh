#!/bin/sh
set -eu

# Install common dependencies for CI steps.
# Adapted from scripts/ci-setup.sh for GitLab CI (Alpine-based).
apk add --no-cache bash git python3 py3-yaml zsh make curl ca-certificates coreutils

# Install SAST-specific tools when requested.
if [ "${1:-}" = "sast" ]; then
  apk add --no-cache shellcheck shfmt
  # uv is not in Alpine's repos; installed per-job in .ci/gitlab-ci.yml
  # via official installer (curl | sh)
fi

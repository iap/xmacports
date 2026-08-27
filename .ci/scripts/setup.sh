#!/bin/sh
set -eu

# Install common dependencies for CI steps.
# Adapted from scripts/ci-setup.sh for GitLab CI (Alpine-based).
apk add --no-cache bash git python3 py3-yaml zsh make curl ca-certificates coreutils

# Install SAST-specific tools when requested.
if [ "${1:-}" = "sast" ]; then
  apk add --no-cache shellcheck shfmt
  # ruff is not in Alpine's repos; install uv and use `uv tool run ruff`
  # (the Makefile's python-lint target already handles this fallback).
  apk add --no-cache uv
fi

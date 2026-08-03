#!/usr/bin/env bash
set -euo pipefail

# Install common dependencies for CI steps.
apk add --no-cache bash git python3 py3-yaml zsh make curl ca-certificates age coreutils

# Install SAST-specific tools when requested.
if [ "${1:-}" = "sast" ]; then
  apk add --no-cache shellcheck shfmt
fi

# Install pinned sops binary with SHA256 verification.
curl -fsSL https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64 -o /tmp/sops
echo "5488e32bc471de7982ad895dd054bbab3ab91c417a118426134551e9626e4e85  /tmp/sops" | sha256sum -c -
chmod +x /tmp/sops
mv /tmp/sops /usr/local/bin/sops

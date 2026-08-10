#!/bin/bash
# Verify Drone CI build status for the authoritative dotfiles repo.
#
# Context: Drone reports commit status to GitLab via the GitLab *Status API*,
# NOT GitLab CI pipelines. GitLab's MR "status" API/UI therefore cannot surface
# Drone builds (it 404s for them), so the authoritative source of truth is the
# Drone server itself. This script reads the Drone server URL + API token from
# the SOPS store (drone namespace) and runs `drone build ls`, exiting 0 only
# when the latest build matches the expected status (default: success).
#
# Usage:
#   scripts/drone-check.sh                         # latest build must be 'success'
#   scripts/drone-check.sh --status success --limit 1
#   scripts/drone-check.sh --repo iap/xmacports --branch main
#   scripts/drone-check.sh --event pull_request
#
# Credentials come from the encrypted SOPS store (drone.server, drone.token).
# Env: DOTFILES_ROOT (default $HOME/.dotfiles).

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# Source platform + secrets helpers. Both are safe under set -u (all reads
# defaulted), and secrets.sh provides the `secret` function used below.
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shared/platform.sh"
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shared/secrets.sh"

require() {
  if ! command -v "$1" > /dev/null 2>&1; then
    echo "ERROR: required tool not found: $1" >&2
    echo "Fix: download drone_darwin_$(uname -m) from" >&2
    echo "      https://github.com/harness/drone-cli/releases/latest into ~/bin" >&2
    exit 1
  fi
}

require drone

# --- argument parsing ---
REPO="iap/xmacports"
BRANCH=""
EVENT=""
STATUS="success"
LIMIT=1

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --event)
      EVENT="${2:-}"
      shift 2
      ;;
    --status)
      STATUS="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    -h | --help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# --- resolve credentials from the SOPS store ---
# `|| true` keeps set -e from aborting before the friendly empty-check below.
DRONE_SERVER="$(secret server drone || true)"
DRONE_TOKEN="$(secret token drone || true)"

if [ -z "$DRONE_SERVER" ] || [ -z "$DRONE_TOKEN" ]; then
  echo "ERROR: drone server/token not found in SOPS store (namespace: drone)" >&2
  echo "Fix: add 'drone: { server: ..., token: ... }' to secrets/secrets.yaml" >&2
  echo "      and re-encrypt with 'make secrets-encrypt'." >&2
  exit 1
fi

# --- assemble and run the drone command ---
args=(--server "$DRONE_SERVER" --token "$DRONE_TOKEN" build ls --limit "$LIMIT")
[ -n "$BRANCH" ] && args+=(--branch "$BRANCH")
[ -n "$EVENT" ] && args+=(--event "$EVENT")

echo "Drone build status for $REPO (server: $DRONE_SERVER)"
echo

# drone prints a header row, then data rows. Capture so we can both show and parse.
OUT="$(drone "${args[@]}" "$REPO")"
echo "$OUT"
echo

# Drop the header (first line); take the first data row; STATUS is column 2.
latest="$(printf '%s\n' "$OUT" | awk 'NR==1{next} NF{print; exit}')"
if [ -z "$latest" ]; then
  echo "FAIL: no builds found for $REPO"
  exit 1
fi

latest_status="$(printf '%s\n' "$latest" | awk '{print $2}')"

if [ "$latest_status" = "$STATUS" ]; then
  echo "PASS: latest build status is '$latest_status' (expected '$STATUS')"
  exit 0
else
  echo "FAIL: latest build status is '$latest_status' (expected '$STATUS')"
  exit 1
fi

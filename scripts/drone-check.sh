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
#   scripts/drone-check.sh                         # latest build must be 'success' AND cover HEAD
#   scripts/drone-check.sh --status success --limit 1
#   scripts/drone-check.sh --no-coverage           # skip the HEAD-coverage check
#   scripts/drone-check.sh --repo iap/xmacports --branch main
#   scripts/drone-check.sh --event pull_request
#
# A green status alone is not enough: if webhook-driven builds stop firing,
# `drone build ls` keeps showing an old green build forever while new commits
# on main ship untested. The default check therefore also requires that the
# latest build's commit matches this clone's upstream HEAD; pass --no-coverage
# to opt out (e.g. checking a PR event build for a topic branch).
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
CHECK_COVERAGE=1

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
    --no-coverage)
      CHECK_COVERAGE=0
      shift
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
# Explicit DRONE_SERVER/DRONE_TOKEN env vars win (used by tests/automation);
# otherwise they are read from the encrypted store (namespace: drone).
# `|| true` keeps set -e from aborting before the friendly empty-check below.
DRONE_SERVER="${DRONE_SERVER:-$(secret server drone || true)}"
DRONE_TOKEN="${DRONE_TOKEN:-$(secret token drone || true)}"

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

# Parse the FIRST build entry. `drone build ls` prints labeled multi-line
# blocks ("Build #N", "Status: success", "Commit: <sha>", ...) with ANSI color
# codes, which are stripped before parsing. Take each field from its label
# inside the first block; fall back to positional columns for CLI versions
# that print a table instead.
latest=""
first_block="$(printf '%s\n' "$OUT" | sed $'s/\033\[[0-9;]*m//g' | sed -n '/^Build #/,$p' | awk '/^$/{exit} {print}')"

if printf '%s\n' "$first_block" | grep -q '^Status:'; then
  latest_status="$(printf '%s\n' "$first_block" | awk '/^Status:/{print $2; exit}')"
else
  # Table layout: header row dropped, first data row, status is column 2.
  latest="$(printf '%s\n' "$OUT" | awk 'NR==1{next} NF{print; exit}')"
  [ -n "$latest" ] || {
    echo "FAIL: no builds found for $REPO"
    exit 1
  }
  latest_status="$(printf '%s\n' "$latest" | awk '{print $2}')"
fi

if [ "$latest_status" != "$STATUS" ]; then
  echo "FAIL: latest build status is '$latest_status' (expected '$STATUS')"
  exit 1
fi
echo "PASS: latest build status is '$latest_status' (expected '$STATUS')"

# --- HEAD-coverage check ---
# The newest build must be FOR this clone's upstream HEAD, not merely green.
# Without this, a stalled mirror/webhook leaves an old green build in place
# while main ships untested commits. The comparison target is the tracked
# upstream of the --branch argument when given, else the current branch's
# upstream, else origin/main. A stale local ref fails the gate with a hint
# to fetch — a stale clone cannot silently pass as covered.
if [ "$CHECK_COVERAGE" -eq 0 ]; then
  exit 0
fi

if [ -n "$BRANCH" ]; then
  UP="origin/$BRANCH"
else
  UP="$(git -C "$DOTFILES_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null || true)"
fi
if [ -z "$UP" ]; then
  UP="origin/main"
fi

HEAD_SHA="$(git -C "$DOTFILES_ROOT" rev-parse --verify "$UP" 2> /dev/null || true)"
if [ -z "$HEAD_SHA" ]; then
  echo "FAIL: cannot resolve upstream ref '$UP' to compare against the build commit"
  echo "Fix: run 'git fetch' so the local clone knows its upstream state."
  exit 1
fi

build_commit="$(printf '%s\n' "$first_block" | awk '/^Commit:/{print $2; exit}')"
if [ -z "$build_commit" ]; then
  # Table-layout fallback: first data row, commit SHA is column 3.
  build_commit="$(printf '%s\n' "$latest" | awk '{print $3}')"
fi
case "$build_commit" in
  "$HEAD_SHA")
    echo "PASS: latest build covers upstream HEAD ($HEAD_SHA)"
    ;;
  *)
    if git -C "$DOTFILES_ROOT" merge-base --is-ancestor "$build_commit" "$HEAD_SHA" 2> /dev/null; then
      behind_count="$(git -C "$DOTFILES_ROOT" rev-list --count "$build_commit..$HEAD_SHA")"
      echo "FAIL: latest build ($build_commit) is $behind_count commit(s) behind $UP ($HEAD_SHA) — CI has not covered HEAD."
      echo "Fix: check that the tildegit mirror is in sync and the Drone webhook fired for the latest push."
      exit 1
    fi
    echo "FAIL: latest build ($build_commit) is not an ancestor of $UP ($HEAD_SHA)"
    exit 1
    ;;
esac

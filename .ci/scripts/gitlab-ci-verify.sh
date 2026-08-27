#!/bin/bash
# Verify GitLab CI pipeline status for the authoritative dotfiles repo.
#
# GitLab CI reports pipeline status natively to GitLab's commit/MR UI — no
# Status API workaround needed (unlike Drone). This script reads the latest
# pipeline for the current branch via the GitLab API and exits 0 only when
# the latest pipeline is green AND covers the current HEAD.
#
# Usage:
#   .ci/scripts/gitlab-ci-verify.sh                         # latest pipeline must be 'success' AND cover HEAD
#   .ci/scripts/gitlab-ci-verify.sh --no-coverage           # skip the HEAD-coverage check
#   .ci/scripts/gitlab-ci-verify.sh --branch main           # check a specific branch
#   .ci/scripts/gitlab-ci-verify.sh --status success        # expected status (default: success)
#
# Env: DOTFILES_ROOT (default $HOME/.dotfiles), GITLAB_TOKEN (for private repos)

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# Source platform helpers
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shared/platform.sh"

# --- argument parsing ---
BRANCH=""
STATUS="success"
CHECK_COVERAGE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --status)
      STATUS="${2:-}"
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

# --- resolve branch ---
if [ -z "$BRANCH" ]; then
  BRANCH="$(git -C "$DOTFILES_ROOT" rev-parse --abbrev-ref HEAD 2> /dev/null || true)"
fi
[ -n "$BRANCH" ] || {
  echo "ERROR: cannot determine branch" >&2
  exit 1
}

echo "GitLab CI pipeline status for $BRANCH"

# --- query GitLab API ---
# Use glab CLI if available (authenticated), otherwise curl with token
API_BASE="https://gitlab.com/api/v4"
PROJECT_PATH="iap/xmacports"
ENCODED_PATH="$(printf '%s' "$PROJECT_PATH" | jq -sRr @uri 2> /dev/null || echo "$PROJECT_PATH")"

if command -v glab > /dev/null 2>&1; then
  # glab is authenticated — use it
  PIPELINE_JSON="$(glab api "projects/$ENCODED_PATH/pipelines?ref=$BRANCH&per_page=1" 2> /dev/null || echo "[]")"
else
  # Fall back to curl with optional token
  if [ -n "${GITLAB_TOKEN:-}" ]; then
    PIPELINE_JSON="$(curl -fsS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API_BASE/projects/$ENCODED_PATH/pipelines?ref=$BRANCH&per_page=1" 2> /dev/null || echo "[]")"
  else
    PIPELINE_JSON="$(curl -fsS "$API_BASE/projects/$ENCODED_PATH/pipelines?ref=$BRANCH&per_page=1" 2> /dev/null || echo "[]")"
  fi
fi

# --- parse latest pipeline ---
LATEST_STATUS="$(echo "$PIPELINE_JSON" | jq -r '.[0].status // empty' 2> /dev/null || true)"
LATEST_SHA="$(echo "$PIPELINE_JSON" | jq -r '.[0].sha // empty' 2> /dev/null || true)"
LATEST_ID="$(echo "$PIPELINE_JSON" | jq -r '.[0].id // empty' 2> /dev/null || true)"

if [ -z "$LATEST_STATUS" ] || [ "$LATEST_STATUS" = "null" ]; then
  echo "FAIL: no pipelines found for branch '$BRANCH'"
  exit 1
fi

echo "Pipeline #$LATEST_ID: status=$LATEST_STATUS sha=$LATEST_SHA"

if [ "$LATEST_STATUS" != "$STATUS" ]; then
  echo "FAIL: latest pipeline status is '$LATEST_STATUS' (expected '$STATUS')"
  exit 1
fi
echo "PASS: latest pipeline status is '$LATEST_STATUS'"

# --- HEAD-coverage check ---
if [ "$CHECK_COVERAGE" -eq 0 ]; then
  exit 0
fi

HEAD_SHA="$(git -C "$DOTFILES_ROOT" rev-parse --verify HEAD 2> /dev/null || true)"
if [ -z "$HEAD_SHA" ]; then
  echo "FAIL: cannot resolve HEAD"
  exit 1
fi

if [ "$LATEST_SHA" = "$HEAD_SHA" ]; then
  echo "PASS: latest pipeline covers HEAD ($HEAD_SHA)"
else
  echo "FAIL: latest pipeline ($LATEST_SHA) does not match HEAD ($HEAD_SHA)"
  echo "Fix: wait for the latest pipeline to complete, or check if the webhook fired."
  exit 1
fi

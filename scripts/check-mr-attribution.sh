#!/bin/sh
# Fetch a merge request's description from the GitLab API and run the attribution
# gate over it.
#
# Why this exists: the commit-msg hook guards commit messages, but an MR
# description is not part of git - it is submitted to the forge and the local
# hooks never see it. That gap is exactly how a false "Generated with Claude
# Code" footer reached MR !37, and it is why three prose warnings failed to stop
# it. This script closes the gap from the CI side: it runs on GitLab's runners,
# for every MR, regardless of who opened it or what is installed locally, so it
# cannot be skipped the way a local hook can.
#
# Usage:
#   scripts/check-mr-attribution.sh <project-id> <mr-iid>
#
# Environment:
#   CI_API_V4_URL / GITLAB_API_URL  API base (default https://gitlab.com/api/v4)
#   GITLAB_API_TOKEN                 preferred token
#   CI_JOB_TOKEN                     fallback token
#
# Exit 0 = description is clean, 1 = attribution found, 2 = could not verify.
#
# Fail-CLOSED on "could not verify" (exit 2, which CI treats as a failure): a
# gate that quietly passes when it cannot run is worse than no gate, because it
# reports safety it did not establish. SKIP_MR_ATTRIBUTION_CHECK=1 is the
# explicit, greppable override.

set -u

PROJECT="${1:-}"
MR_IID="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$MR_IID" ]; then
  echo "usage: $0 <project-id> <mr-iid>" >&2
  exit 2
fi

CHECK="$(dirname "$0")/check-attribution.sh"
if [ ! -r "$CHECK" ]; then
  echo "ERROR: check-attribution.sh not found next to this script" >&2
  exit 2
fi

if [ "${SKIP_MR_ATTRIBUTION_CHECK:-0}" != "0" ]; then
  echo "MR attribution check skipped (SKIP_MR_ATTRIBUTION_CHECK set)" >&2
  exit 0
fi

API="${CI_API_V4_URL:-${GITLAB_API_URL:-https://gitlab.com/api/v4}}"
API="${API%/}"

TOKEN="${GITLAB_API_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: no API token available (set GITLAB_API_TOKEN or CI_JOB_TOKEN)." >&2
  echo "Cannot fetch the MR description, so it cannot be verified." >&2
  exit 2
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/mrdesc.XXXXXX")" || exit 2
trap 'rm -f "$TMP" "$TMP.json"' EXIT INT TERM

url="${API}/projects/${PROJECT}/merge_requests/${MR_IID}"

# Send both header forms. A PAT is accepted as PRIVATE-TOKEN; an OAuth token
# (what `glab auth login` stores for gitlab.com) is only accepted as a Bearer.
# Sending an unused header is harmless, so this avoids a 401 that depends on
# which kind of token the environment holds.
#
# Fetch to a file; never interpolate the description into the shell. A
# description is attacker-controlled text, and `eval`/backtick expansion on it
# would turn a text field into code execution.
fetched=""
if curl -fsS -H "PRIVATE-TOKEN: ${TOKEN}" -H "Authorization: Bearer ${TOKEN}" \
  "$url" -o "$TMP.json" 2> /dev/null; then
  fetched=yes
else
  # Retry without auth: public projects allow an anonymous read. CI_JOB_TOKEN
  # is scoped to the pipeline and cannot always read the MR endpoint.
  if curl -fsS "$url" -o "$TMP.json" 2> /dev/null; then
    fetched=anonymous
  fi
fi

if [ -z "$fetched" ]; then
  echo "ERROR: could not fetch MR !${MR_IID} from ${url}" >&2
  echo "Treating an unverifiable description as a FAILURE, not a pass." >&2
  exit 2
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required to parse the API response" >&2
  exit 2
fi

# -r writes the raw string; redirection to a file keeps it out of the shell.
if ! jq -er '.description // ""' "$TMP.json" > "$TMP" 2> /dev/null; then
  echo "ERROR: API response for MR !${MR_IID} has no usable description field" >&2
  exit 2
fi

echo "Fetched MR !${MR_IID} description: $(wc -c < "$TMP" | tr -d ' ') bytes"

# The gate itself. Exits 1 and names the offending line.
sh "$CHECK" --message-file "$TMP"

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

# Only the exact value 1 opts out; an incidental value must not disable the
# gate. CodeRabbit flags this as CWE-693 and suggests restricting it further via
# CODEOWNERS on the CI file. That is a reasonable follow-up, but the variable is
# not attacker-controlled: setting it requires an edit to a tracked file or a
# pipeline variable, both of which are reviewable. The exact-match check closes
# the accidental-value hole, which is the part that could bite silently.
if [ "${SKIP_MR_ATTRIBUTION_CHECK:-0}" = "1" ]; then
  echo "MR attribution check skipped (SKIP_MR_ATTRIBUTION_CHECK=1)" >&2
  exit 0
fi

# An explicit GITLAB_API_URL override must WIN over the ambient CI_API_V4_URL.
# GitLab always sets CI_API_V4_URL inside a pipeline, so preferring it made this
# script ignore the test's stub server and query the real API instead - which
# turns every "clean description passes" case into a fetch failure. Checking the
# explicit override first is what lets the suite point the script at a stub.
API="${GITLAB_API_URL:-${CI_API_V4_URL:-https://gitlab.com/api/v4}}"
API="${API%/}"

TOKEN="${GITLAB_API_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: no API token available (set GITLAB_API_TOKEN or CI_JOB_TOKEN)." >&2
  echo "Cannot fetch the MR description, so it cannot be verified." >&2
  exit 2
fi

# Both temp files come from mktemp. Deriving the JSON path as "$TMP.json" made it
# predictable (CWE-377): in a shared TMPDIR another user could pre-create it as a
# symlink and have curl write through it.
TMP="$(mktemp "${TMPDIR:-/tmp}/mrdesc.XXXXXX")" || exit 2
JSON="$(mktemp "${TMPDIR:-/tmp}/mrdesc-json.XXXXXX")" || exit 2
trap 'rm -f "$TMP" "$JSON"' EXIT INT TERM

url="${API}/projects/${PROJECT}/merge_requests/${MR_IID}"

# Both header forms: a PAT is accepted as PRIVATE-TOKEN, an OAuth token (what
# `glab auth login` stores) only as Bearer. An unused header is harmless, so this
# avoids a 401 that would otherwise depend on which token kind is held.
#
# Fetch to a file; never interpolate the description into the shell. A
# description is attacker-controlled text, and `eval`/backtick expansion on it
# would turn a text field into code execution.
#
# curl's stderr is captured rather than discarded: when both attempts fail the
# job would otherwise report only "could not fetch", hiding whether the cause was
# a 404, a 401 or a DNS failure.
err="$(mktemp "${TMPDIR:-/tmp}/mrdesc-err.XXXXXX")" || exit 2

fetched=""
if curl -fsS -H "PRIVATE-TOKEN: ${TOKEN}" -H "Authorization: Bearer ${TOKEN}" \
  "$url" -o "$JSON" 2> "$err"; then
  fetched=yes
else
  # Retry without auth: public projects allow an anonymous read. CI_JOB_TOKEN is
  # scoped to the pipeline and cannot always read the MR endpoint.
  if curl -fsS "$url" -o "$JSON" 2> "$err"; then
    fetched=anonymous
  fi
fi

if [ -z "$fetched" ]; then
  echo "ERROR: could not fetch MR !${MR_IID} from ${url}" >&2
  if [ -s "$err" ]; then
    echo "curl reported:" >&2
    sed 's/^/  /' "$err" >&2
  fi
  echo "Treating an unverifiable description as a FAILURE, not a pass." >&2
  rm -f "$err"
  exit 2
fi
rm -f "$err"

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required to parse the API response" >&2
  exit 2
fi

# -r writes the raw string; redirection to a file keeps it out of the shell.
if ! jq -er '.description // ""' "$JSON" > "$TMP" 2> /dev/null; then
  echo "ERROR: API response for MR !${MR_IID} has no usable description field" >&2
  exit 2
fi

echo "Fetched MR !${MR_IID} description: $(wc -c < "$TMP" | tr -d ' ') bytes"

# The gate itself. Exits 1 and names the offending line.
sh "$CHECK" --message-file "$TMP"

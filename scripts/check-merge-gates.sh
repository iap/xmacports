#!/bin/sh
# Verify that an MR's merge gates are armed and that its review conversation is
# resolved.
#
# Why this exists: the merge policy lives in two places git cannot see. The
# FORGE decides whether the merge button is enabled at all (project settings:
# only_allow_merge_if_all_discussions_are_resolved,
# only_allow_merge_if_pipeline_succeeds, and force-push protection on the target
# branch), and the CONVERSATION decides whether there is anything left to
# resolve. Both are outside the repository, so no local hook can check either,
# and both decay silently: a toggled setting looks exactly like a satisfied one
# until the day it lets an unresolved MR through. This script reads them back and
# fails when any of them is not what CONTRIBUTING.md, "Merge gates", promises.
#
# What it deliberately does NOT check: the approvals endpoint. This project
# requires zero approvals, so GitLab answers `approved: true` for an MR nobody
# reviewed - the check is vacuous, and honoring it would report a review that
# never happened. Resolved discussions are the record.
#
# Usage:
#   scripts/check-merge-gates.sh <project-id> <mr-iid>
#
# Environment:
#   GITLAB_API_URL / CI_API_V4_URL  API base (default https://gitlab.com/api/v4)
#   GITLAB_API_TOKEN                 preferred token
#   CI_JOB_TOKEN                     fallback token
#   SKIP_MERGE_GATES_CHECK=1         explicit opt-out (state it in the MR)
#
# Exit 0 = gates armed and conversation resolved, 1 = a gate is not satisfied,
# 2 = could not verify (a failure: an unverified gate is not a passing gate).

set -u

PROJECT="${1:-}"
MR_IID="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$MR_IID" ]; then
  echo "usage: $0 <project-id> <mr-iid>" >&2
  exit 2
fi

# Only the exact value 1 opts out; an incidental value must not disable a gate.
# Same reasoning, and the same CWE-693 caveat, as check-mr-attribution.sh: the
# variable is not attacker-controlled, but exact-match closes the accidental-value
# hole, which is the part that could bite silently.
if [ "${SKIP_MERGE_GATES_CHECK:-0}" = "1" ]; then
  echo "Merge-gates check skipped (SKIP_MERGE_GATES_CHECK=1)" >&2
  exit 0
fi

# An explicit GITLAB_API_URL override must WIN over the ambient CI_API_V4_URL, or
# the suite's stub server is ignored and the real API is queried instead.
API="${GITLAB_API_URL:-${CI_API_V4_URL:-https://gitlab.com/api/v4}}"
API="${API%/}"

TOKEN="${GITLAB_API_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: no API token available (set GITLAB_API_TOKEN or CI_JOB_TOKEN)." >&2
  echo "The merge gates cannot be read, so they cannot be verified." >&2
  exit 2
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq is required to parse the API response" >&2
  exit 2
fi

# Every scratch path comes from mktemp. Deriving one from a predictable name
# (CWE-377) lets another user on a shared TMPDIR pre-create a symlink and have
# curl write through it. All are named in the trap so the early-exit paths
# (including the ones before the trap is installed) do not leak files.
PROJ="$(mktemp "${TMPDIR:-/tmp}/mrgates-proj.XXXXXX")" || exit 2
MR="$(mktemp "${TMPDIR:-/tmp}/mrgates-mr.XXXXXX")" || exit 2
PROT="$(mktemp "${TMPDIR:-/tmp}/mrgates-prot.XXXXXX")" || exit 2
DISC="$(mktemp "${TMPDIR:-/tmp}/mrgates-disc.XXXXXX")" || exit 2
err="$(mktemp "${TMPDIR:-/tmp}/mrgates-err.XXXXXX")" || exit 2
# Separate file for the AUTHENTICATED attempt. Both attempts used to redirect
# into $err, so a failing token request was overwritten by the anonymous retry
# and vanished on success - leaving a broken or expired CI_JOB_TOKEN with no
# trace at all, which is exactly the failure this script could not explain.
err_auth="$(mktemp "${TMPDIR:-/tmp}/mrgates-err-auth.XXXXXX")" || exit 2
trap 'rm -f "$PROJ" "$MR" "$PROT" "$DISC" "$err" "$err_auth"' EXIT INT TERM

failed=0

# A known violation is more actionable than an unverifiable check, so it wins the
# exit code: mark_violation never overwrites a 2, and mark_unverified never
# overwrites anything. Both still fail the job.
mark_violation() {
  [ "$failed" -eq 2 ] || failed=1
  return 0
}

mark_unverified() {
  [ "$failed" -eq 0 ] && failed=2
  return 0
}

# fetch <url> <dest> <label>
#
# Both header forms: a PAT is accepted as PRIVATE-TOKEN, an OAuth token (what
# `glab auth login` stores) only as Bearer. An unused header is harmless, so
# this avoids a 401 that would otherwise depend on which token kind is held.
# Anonymous retry because the project is public and CI_JOB_TOKEN is scoped to the
# pipeline. Bodies go to files and are never interpolated into the shell: a
# discussion body is attacker-controlled text.
fetch() {
  _f_url="$1"
  _f_dest="$2"
  _f_label="$3"
  if curl -fsS -H "PRIVATE-TOKEN: ${TOKEN}" -H "Authorization: Bearer ***" \
    "$_f_url" -o "$_f_dest" 2> "$err_auth"; then
    return 0
  fi
  if curl -fsS "$_f_url" -o "$_f_dest" 2> "$err"; then
    # The anonymous read worked, so this fetch is not a failure. The
    # authenticated attempt still was, though, and that is worth saying out
    # loud: it is the difference between "the token is valid but not needed"
    # and "the token is broken and this check is running degraded". A 401 here
    # is usually why a policy field looks absent further down.
    if [ -s "$err_auth" ]; then
      echo "note: authenticated read of ${_f_label} failed; fell back to an" >&2
      echo "      anonymous read, so a broken or expired token would go" >&2
      echo "      unnoticed here. That attempt reported:" >&2
      sed 's/^/      /' "$err_auth" >&2
    fi
    return 0
  fi
  echo "ERROR: could not fetch ${_f_label} from ${_f_url}" >&2
  # Both attempts failed; report the authenticated one too, not just the last.
  if [ -s "$err_auth" ]; then
    echo "  authenticated attempt reported:" >&2
    sed 's/^/    /' "$err_auth" >&2
  fi
  if [ -s "$err" ]; then
    echo "  anonymous attempt reported:" >&2
    sed 's/^/    /' "$err" >&2
  fi
  echo "Treating unverifiable merge gates as a FAILURE, not a pass." >&2
  return 2
}

# require_true <json-file> <field> <human label>
#
# A MISSING field is "cannot verify", not "false": an API that stops returning
# the setting has not told us the guarantee holds.
require_true() {
  _r_file="$1"
  _r_field="$2"
  _r_label="$3"
  if ! jq -e "has(\"${_r_field}\")" "$_r_file" > /dev/null 2>&1; then
    echo "ERROR: response has no '${_r_field}' field; cannot verify ${_r_label}." >&2
    mark_unverified
    return 0
  fi
  _r_val="$(jq -r ".${_r_field}" "$_r_file")"
  if [ "$_r_val" = "true" ]; then
    echo "ok   ${_r_label} (${_r_field}=true)"
    return 0
  fi
  echo "FAIL ${_r_label}: ${_r_field}=${_r_val}" >&2
  mark_violation
  return 0
}

# --- project-level policy ---------------------------------------------------
# These decide whether GitLab lets the merge button be pressed at all.
proj_url="${API}/projects/${PROJECT}"
fetch "$proj_url" "$PROJ" "project ${PROJECT}" || exit 2

require_true "$PROJ" "only_allow_merge_if_all_discussions_are_resolved" \
  "an unresolved thread blocks the merge"
require_true "$PROJ" "only_allow_merge_if_pipeline_succeeds" \
  "a red pipeline blocks the merge"

# --- the MR itself ----------------------------------------------------------
mr_url="${API}/projects/${PROJECT}/merge_requests/${MR_IID}"
fetch "$mr_url" "$MR" "MR !${MR_IID}" || exit 2

if ! jq -e 'type == "object" and has("blocking_discussions_resolved")' "$MR" > /dev/null 2>&1; then
  echo "ERROR: MR !${MR_IID} response has no usable 'blocking_discussions_resolved'." >&2
  mark_unverified
else
  # The summary field is the cheap authoritative read. The discussions listing
  # below is a second, independent one: where the two disagree, the honest
  # answer is that we do not know, not the convenient one.
  if [ "$(jq -r '.blocking_discussions_resolved' "$MR")" = "true" ]; then
    echo "ok   MR !${MR_IID} reports no unresolved blocking threads"
  else
    echo "FAIL MR !${MR_IID} still has unresolved discussions" >&2
    echo "     Answer every thread, then resolve it. Do not merge over an open one." >&2
    mark_violation
  fi
fi

# per_page=100 is the documented maximum. A page that comes back full might be
# truncated, so it is reported as unverifiable rather than as a clean listing -
# but only when the visible part is clean, since an open thread on page one is
# already a verdict.
disc_url="${API}/projects/${PROJECT}/merge_requests/${MR_IID}/discussions?per_page=100"
if fetch "$disc_url" "$DISC" "discussions for MR !${MR_IID}"; then
  if ! jq -e 'type == "array"' "$DISC" > /dev/null 2>&1; then
    echo "ERROR: discussions response for MR !${MR_IID} is not a JSON array." >&2
    mark_unverified
  else
    open="$(jq '[.[] | .notes[]? | select(.resolvable == true and .resolved != true)] | length' "$DISC")"
    total="$(jq 'length' "$DISC")"
    if [ "$open" -gt 0 ]; then
      echo "FAIL ${open} resolvable thread(s) still open on MR !${MR_IID}" >&2
      jq -r '.[] | .notes[]? | select(.resolvable == true and .resolved != true) |
        "     - \(.author.username // "unknown"): \(.body | split("\n")[0] | .[0:60])"' \
        "$DISC" >&2
      mark_violation
    elif [ "$total" -ge 100 ]; then
      echo "ERROR: MR !${MR_IID} returned ${total} discussions (the per_page maximum)." >&2
      echo "The listing may be truncated; refusing to call a partial list clean." >&2
      mark_unverified
    else
      echo "ok   no open resolvable threads in the discussions listing (${total} checked)"
    fi
  fi
else
  mark_unverified
fi

# --- force-push protection on the target branch -----------------------------
# The other half of "published history is immutable": a protected branch with
# force push enabled still loses commits. Read from the MR's own target so the
# check cannot drift onto a branch the MR is not going to.
target="$(jq -r '.target_branch // empty' "$MR" 2> /dev/null || true)"
if [ -z "$target" ]; then
  echo "ERROR: MR !${MR_IID} response names no target_branch; cannot verify force-push protection." >&2
  mark_unverified
else
  prot_url="${API}/projects/${PROJECT}/protected_branches/$(printf '%s' "$target" | jq -sRr @uri)"
  if fetch "$prot_url" "$PROT" "protected branch '${target}'"; then
    if ! jq -e 'has("allow_force_push")' "$PROT" > /dev/null 2>&1; then
      echo "ERROR: protected-branch response for '${target}' has no 'allow_force_push'." >&2
      mark_unverified
    else
      fp="$(jq -r '.allow_force_push' "$PROT")"
      if [ "$fp" = "false" ]; then
        echo "ok   force push is disabled on '${target}'"
      else
        echo "FAIL force push is ENABLED on '${target}'" >&2
        echo "     Published signed history could be rewritten. See CONTRIBUTING.md." >&2
        mark_violation
      fi
    fi
  else
    mark_unverified
  fi
fi

case "$failed" in
  0)
    echo "PASS merge gates armed and conversation resolved"
    exit 0
    ;;
  1)
    echo "FAIL merge gates not satisfied (see above)" >&2
    exit 1
    ;;
  *)
    echo "FAIL merge gates could not be verified (see above)" >&2
    exit 2
    ;;
esac

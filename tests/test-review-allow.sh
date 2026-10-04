#!/usr/bin/env bash
# Tests for .review-allow, the named list of apps permitted to supply the
# approving review for a merge request.
#
# This is not the merge trigger: an MR merges when its review conversation is
# resolved, which git cannot see and no local gate can check. What the file
# records is the stronger approval requirement for the day a second reviewer
# exists, so the only thing a local test can defend is the record's own
# integrity - that it stays present, tracked, and no wider than it was written.
#
# A gate that cannot fail is worse than no gate, so each case below asserts a
# concrete property. An empty list is a legitimate fail-closed state and is
# deliberately NOT treated as a failure; the file exists to name an approver,
# and refusing to let anyone be named until a second collaborator exists would
# make the record unwritable rather than safe.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOW="$ROOT/.review-allow"

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  echo "  ok   $1"
}

no() {
  fail=$((fail + 1))
  echo "  FAIL $1"
}

# --- present ---------------------------------------------------------------
# Tracked on purpose: it is the auditable record of WHO may approve, so an
# untracked copy is invisible to every other clone and to the maintainer's own
# review of a change to this policy. Same reasoning as .attribution-allow.
if [ -f "$ALLOW" ]; then
  ok ".review-allow is present in the repo"
else
  no ".review-allow is present in the repo"
fi

if git -C "$ROOT" ls-files --error-unmatch .review-allow > /dev/null 2>&1; then
  ok ".review-allow is tracked by git"
else
  no ".review-allow is tracked by git"
fi

if [ -r "$ALLOW" ]; then
  ok ".review-allow is readable"
else
  no ".review-allow is readable"
fi

# --- every entry names an account, not a pattern ---------------------------
# These are the failure modes the file's own comment forbids. Each would widen
# the record silently, which is the one thing a named allowlist exists to
# prevent: "any installed app" is exactly the policy this replaced.
#
# A GitHub app submits reviews as `some-app[bot]`; a GitLab project as
# `project+bot`. Neither contains a glob character, an @, or internal
# whitespace, so all three checks below are safe across both forges.
if [ -r "$ALLOW" ]; then
  entries=0
  bad_glob=0
  bad_at=0
  bad_space=0
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%%#*}"
    # Trim, then skip: blank lines and #-comments are ignored by design.
    entry="$(printf '%s' "$entry" | awk '{$1=$1};1')"
    [ -n "$entry" ] || continue
    entries=$((entries + 1))
    case "$entry" in
      *\**) bad_glob=$((bad_glob + 1)) ;;
    esac
    case "$entry" in
      *@*) bad_at=$((bad_at + 1)) ;;
    esac
    case "$entry" in
      *[[:space:]]*) bad_space=$((bad_space + 1)) ;;
    esac
  done < "$ALLOW"

  if [ "$bad_glob" -eq 0 ]; then
    ok "no entry is a glob pattern"
  else
    no "no entry is a glob pattern ($bad_glob bad)"
  fi

  if [ "$bad_at" -eq 0 ]; then
    ok "no entry is an email address rather than an account"
  else
    no "no entry is an email address rather than an account ($bad_at bad)"
  fi

  if [ "$bad_space" -eq 0 ]; then
    ok "no entry contains internal whitespace"
  else
    no "no entry contains internal whitespace ($bad_space bad)"
  fi

  if [ "$entries" -eq 0 ]; then
    # Fail-closed, and correct until a real approver exists. Reported so the
    # state is visible in test output rather than inferred from silence.
    echo "  note .review-allow names no approver; only a collaborator can approve"
  else
    ok ".review-allow names $entries approver(s)"
  fi
fi

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

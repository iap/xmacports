#!/bin/sh
# Verify that every commit in a range carries a good GPG signature.
#
# Why this exists: `commit.gpgsign true` is a local preference, and the
# pre-merge `git log --format='%h %G?'` check is a local habit. Push rules
# (reject_unsigned_commits) are not available on this project's GitLab plan, so
# nothing on the forge ever refused an unsigned commit - and a signature is the
# one property a maintainer working alone can still have a machine verify. This
# runs on the forge's runners for every MR, so it does not care what is
# installed locally or whether hooks were bypassed.
#
# WHAT IT PROVES, precisely: each commit is signed and its signature is
# cryptographically good. It does NOT prove the key is trusted. Trust needs a
# keyring, and the runner has none.
#
# The %G? values, and what this accepts:
#   G  good signature, valid                     accept
#   U  good signature, unknown validity          accept
#   N  no signature                              reject
#   B  bad signature                             reject
#   X  good signature, expired                   reject
#   Y  good signature made by an expired key     reject
#   R  good signature made by a revoked key      reject
#   E  cannot be checked                         reject
#
# U is the normal result in CI: the runner imports the signing key's PUBLIC
# half from keys/iap-signing-key.asc, so it can confirm a signature is good but
# cannot reach a trust anchor. Accepting U is what makes the check possible
# without distributing private keys to CI. Requiring G - which does verify trust
# - stays a local check, because that is where the trust anchor is.
#
# Without that import the runner reports E for EVERY commit, correctly signed or
# not, and this gate rejects all of them. The job therefore imports the key; do
# not "fix" an all-E run by accepting E here, which would pass any commit the
# runner cannot check at all.
#
# E is rejected on purpose: "could not be checked" must never read as "pass".
# The CI job installs gnupg so this status means a genuine anomaly rather than
# a missing binary.
#
# Usage:
#   scripts/check-signatures.sh <base> [<head>]
#
# Must be run from the repository root: refs are resolved in the current
# directory, which is the checkout root in the CI job.
#
# Environment, used when arguments are omitted (the MR pipeline's own names):
#   CI_MERGE_REQUEST_DIFF_BASE_SHA  base of the MR range
#   CI_COMMIT_SHA                   head of the MR range
#
# Exit 0 = every commit in the range is signed with a good signature
#        1 = an unsigned, bad, expired, revoked, or unchecked commit exists
#        2 = the range could not be resolved, so nothing was verified
#
# Fail-CLOSED on an unresolvable range (exit 2), for the same reason the
# attribution gates do: an unresolvable base reads as an empty range, and an
# empty range reads as "nothing is unsigned". A gate that passes when it cannot
# establish its own precondition reports safety it does not have.
# SKIP_SIGNATURE_CHECK=1 is the explicit, greppable override.

set -u

BASE="${1:-${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}}"
HEAD="${2:-${CI_COMMIT_SHA:-HEAD}}"

# Only the exact value 1 opts out, so an incidental value cannot disable the
# gate. Same rule as SKIP_MR_ATTRIBUTION_CHECK.
case "${SKIP_SIGNATURE_CHECK:-}" in
  1)
    echo "SKIP_SIGNATURE_CHECK=1 - skipping signature verification"
    exit 0
    ;;
esac

if [ -z "$BASE" ]; then
  echo "usage: $0 <base> [<head>]" >&2
  echo "no base given and CI_MERGE_REQUEST_DIFF_BASE_SHA is unset" >&2
  exit 2
fi

# Resolve the ref BEFORE walking it. A typo, or a base SHA the runner never
# fetched, is indistinguishable from "there are no commits here" - and an empty
# range is exactly what a passing run looks like.
if ! git rev-parse --verify --quiet "${BASE}^{commit}" > /dev/null 2>&1; then
  echo "ERROR: cannot resolve base '${BASE}'." >&2
  echo "That would leave an empty range, which reads as 'nothing unsigned'." >&2
  echo "Refusing to report a result it did not establish." >&2
  exit 2
fi

if ! git rev-parse --verify --quiet "${HEAD}^{commit}" > /dev/null 2>&1; then
  echo "ERROR: cannot resolve head '${HEAD}'." >&2
  exit 2
fi

RANGE="${BASE}..${HEAD}"

if ! COMMITS="$(git rev-list "$RANGE" 2> /dev/null)"; then
  echo "ERROR: cannot list commits in '${RANGE}'." >&2
  exit 2
fi

total=0
bad=0

# Iterate over rev-list output rather than piping `git log` into a read loop: a
# pipe would run the loop in a subshell, and every counter increment would be
# lost - the exact pitfall scripts/attribution-allow.sh documents. rev-list
# emits one bare object name per line, so this needs no field splitting on
# untrusted content.
# shellcheck disable=SC2086
for sha in $COMMITS; do
  total=$((total + 1))

  if ! status="$(git log -1 --format='%G?' "$sha" 2> /dev/null)"; then
    echo "ERROR: cannot read signature status for ${sha}." >&2
    exit 2
  fi

  case "$status" in
    G | U) : ;;
    *)
      bad=$((bad + 1))
      # %s is a folded single-line subject, so this stays one line per commit.
      if ! desc="$(git log -1 --format='%h %an <%ae> %s' "$sha" 2> /dev/null)"; then
        desc="$sha"
      fi
      printf '  [%s] %s\n' "$status" "$desc" >&2
      ;;
  esac
done

if [ "$total" -eq 0 ]; then
  # Legitimate and not a pass-through: an empty MR, or a base equal to head.
  echo "range '${RANGE}' contains no commits - nothing to verify"
  exit 0
fi

if [ "$bad" -gt 0 ]; then
  echo "" >&2
  echo "ERROR: ${bad} of ${total} commit(s) in '${RANGE}' lack a good signature." >&2
  echo "Sign the range: git rebase --exec 'git commit --amend --no-edit -S' ${BASE}" >&2
  exit 1
fi

echo "OK: all ${total} commit(s) in '${RANGE}' carry a good signature"
exit 0

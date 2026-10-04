#!/usr/bin/env bash
# Tests for scripts/check-signatures.sh.
#
# A gate that cannot fail is worse than no gate, so the negative cases come
# first: an unsigned commit MUST be rejected, and an unresolvable range MUST
# NOT be reported as clean. The positive cases then prove the gate is not simply
# rejecting everything.
#
# The signed-commit cases need a throwaway GPG key and are skipped (with a
# visible note, not a silent pass) when gpg cannot produce one - the CI `test`
# runner does not install gnupg, and per AGENTS.md this repository detects
# optional tools rather than installing them.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-signatures.sh"

pass=0
fail=0
TMP=""
export GNUPGHOME=""

setup() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/sig-test.XXXXXX")"
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  # A throwaway keyring, so signing in a test never touches the real one and a
  # commit signed here can never be mistaken for the maintainer's own.
  export GNUPGHOME="$TMP/gnupg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  git -C "$REPO" init -q .
  git -C "$REPO" config user.email "sig-test@example.com"
  git -C "$REPO" config user.name "Sig Test"
  # Unsigned is the DEFAULT here: the rejection cases depend on it. Signing is
  # switched on per-commit by the cases that need it.
  git -C "$REPO" config commit.gpgsign false
}

teardown() {
  [ -n "$TMP" ] && [ -d "$TMP" ] && find "$TMP" -mindepth 1 -delete 2> /dev/null
  [ -n "$TMP" ] && [ -d "$TMP" ] && rmdir "$TMP" 2> /dev/null
  export GNUPGHOME=""
  return 0
}

ok() {
  pass=$((pass + 1))
  echo "  ok   $1"
}

no() {
  fail=$((fail + 1))
  echo "  FAIL $1"
}

# expect_rc <want> <label> <command...>
expect_rc() {
  local want="$1" label="$2"
  shift 2
  "$@" > /dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then
    ok "$label (rc=$got)"
  else
    no "$label (rc=$got, want $want)"
  fi
}

commit_unsigned() {
  git -C "$REPO" commit -q --allow-empty -m "$1"
}

# check_in_repo <args...>
# The script resolves refs in the CURRENT directory, which is the checkout root
# in the CI job. Run it from inside the throwaway repo here, or every base SHA
# this suite invents would be "unresolvable" and the failure cases would pass for
# the wrong reason.
check_in_repo() {
  (cd "$REPO" && sh "$CHECK" "$@")
}

# check_with_skip <skip-value> <args...>
# A subshell rather than `env`, because env can only exec a real binary and
# check_in_repo is a shell function.
check_with_skip() {
  local value="$1"
  shift
  (
    export SKIP_SIGNATURE_CHECK="$value"
    check_in_repo "$@"
  )
}

echo "Running signature-check tests..."
setup
trap teardown EXIT

if [ -x "$CHECK" ]; then ok "check-signatures.sh is executable"; else no "check-signatures.sh is executable"; fi

# --- negative: an unsigned commit must be rejected ------------------------
# This is the case the whole gate exists for. If it ever passes, the gate is
# decorative and everything below is noise.
commit_unsigned "base"
BASE="$(git -C "$REPO" rev-parse HEAD)"
commit_unsigned "unsigned work"
expect_rc 1 "rejects an unsigned commit" \
  check_in_repo "$BASE" HEAD

# The rejection must NAME the offending commit, or a red CI job tells the
# contributor nothing about which commit to fix.
OUT="$(check_in_repo "$BASE" HEAD 2>&1 || true)"
case "$OUT" in
  *"unsigned work"*) ok "rejection names the offending commit" ;;
  *) no "rejection names the offending commit" ;;
esac

# A range with several unsigned commits must report the count, not just the
# first one - otherwise fixing one commit at a time is the only workflow.
commit_unsigned "unsigned work two"
commit_unsigned "unsigned work three"
expect_rc 1 "rejects a range of unsigned commits" \
  check_in_repo "$BASE" HEAD

# --- negative: an unresolvable range must NOT read as clean ---------------
# base..HEAD with an unresolvable base yields nothing to list, and "nothing to
# list" is indistinguishable from "everything is signed". That is the bug this
# case pins.
expect_rc 2 "refuses an unresolvable base (exit 2, not a pass)" \
  check_in_repo no-such-base HEAD
expect_rc 2 "refuses an unresolvable head (exit 2, not a pass)" \
  check_in_repo "$BASE" no-such-head

# A typo'd base in CI would otherwise green-light an MR with zero commits
# checked. The message has to say it refused, not that it passed.
OUT="$(check_in_repo no-such-base HEAD 2>&1 || true)"
case "$OUT" in
  *"cannot resolve"*) ok "unresolvable base explains itself" ;;
  *) no "unresolvable base explains itself" ;;
esac

# --- negative: no base at all --------------------------------------------
expect_rc 2 "requires a base (exit 2)" \
  check_in_repo

# --- positive: an empty range is legitimate, not a failure ---------------
expect_rc 0 "accepts an empty range" \
  check_in_repo "$BASE" "$BASE"

# --- the override is explicit, not incidental ----------------------------
# Only the exact value 1 may disable the gate.
expect_rc 0 "SKIP_SIGNATURE_CHECK=1 skips" \
  check_with_skip 1 no-such-base HEAD
expect_rc 2 "SKIP_SIGNATURE_CHECK=yes does NOT skip" \
  check_with_skip yes no-such-base HEAD
expect_rc 2 "SKIP_SIGNATURE_CHECK=0 does NOT skip" \
  check_with_skip 0 no-such-base HEAD

# --- signed commits -------------------------------------------------------
# The accept path needs a real signature, so it needs a real key. Generate a
# throwaway one and skip the whole block if that is not possible here.
signed_ok=0
if command -v gpg > /dev/null 2>&1 &&
  gpg --batch --quiet --passphrase '' \
    --quick-generate-key "Sig Test <sig-test@example.com>" default default never \
    > /dev/null 2>&1; then
  signed_ok=1
else
  echo "  note gpg unavailable or key generation failed - signed-commit cases skipped"
fi

if [ "$signed_ok" -eq 1 ]; then
  KEY="$(gpg --list-secret-keys --with-colons 2> /dev/null | awk -F: '/^fpr/ {print $10; exit}')"
  if [ -n "$KEY" ]; then
    # Commit signed with the throwaway key. %G? is expected to be G here
    # because the test keyring is the only keyring in play.
    if git -C "$REPO" -c user.signingkey="$KEY" commit -q --allow-empty \
      -S"$KEY" -m "signed work" 2> /dev/null; then
      SIGNED="$(git -C "$REPO" rev-parse HEAD)"
      STATUS="$(git -C "$REPO" log -1 --format='%G?' "$SIGNED" 2> /dev/null)"
      if [ "$STATUS" = "G" ] || [ "$STATUS" = "U" ]; then
        # SIGNED^..SIGNED, not BASE..SIGNED: the earlier commits in that
        # range are unsigned, and this case is about the signed one.
        expect_rc 0 "accepts a signed commit (status ${STATUS})" \
          check_in_repo "$SIGNED^" "$SIGNED"
      else
        no "throwaway key produced a usable signature (status '${STATUS}')"
      fi

      # The mixed range is the case that proves the gate discriminates rather
      # than rejecting every range it is shown.
      expect_rc 1 "rejects a range mixing signed and unsigned commits" \
        check_in_repo "$BASE" HEAD
    else
      no "can create a signed commit with the throwaway key"
    fi
  else
    no "throwaway key has a fingerprint"
  fi
fi

teardown
trap - EXIT

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

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

      # The pubkey-only ring is the CI shape: the runner imports the public
      # half and has no ownertrust, so a good signature reports U. The gate
      # must keep accepting the OpenPGP U - that acceptance is what makes the
      # check possible without private keys on the runner - while an ssh U is
      # rejected (see the ssh cases below).
      mkdir -p "$TMP/gnupg-pub"
      chmod 700 "$TMP/gnupg-pub"
      if gpg --export "$KEY" > "$TMP/pub.gpg" 2> /dev/null &&
        GNUPGHOME="$TMP/gnupg-pub" gpg --batch --quiet --import "$TMP/pub.gpg" > /dev/null 2>&1; then
        # check_pubring <args...>
        check_pubring() {
          (cd "$REPO" && GNUPGHOME="$TMP/gnupg-pub" sh "$CHECK" "$@")
        }
        STATUS_PUB="$(GNUPGHOME="$TMP/gnupg-pub" git -C "$REPO" log -1 --format='%G?' "$SIGNED")"
        if [ "$STATUS_PUB" = "U" ]; then
          ok "pubkey-only ring reports U (status ${STATUS_PUB})"
        else
          no "pubkey-only ring reports U (status ${STATUS_PUB})"
        fi
        expect_rc 0 "accepts an OpenPGP U with a pubkey-only ring" \
          check_pubring "$SIGNED^" "$SIGNED"
      else
        no "can build a pubkey-only ring"
      fi
    else
      no "can create a signed commit with the throwaway key"
    fi
  else
    no "throwaway key has a fingerprint"
  fi
fi

# --- ssh signatures: listed key accepted, unlisted key rejected ----------
# For an ssh signature git consults gpg.ssh.allowedSignersFile: a key listed
# there reports G, and a good signature from a key that is NOT listed reports
# U. That U must be rejected - it is any ssh key - while the OpenPGP U above
# stays accepted. Like the OpenPGP block, this needs a real key and is skipped
# with a visible note when ssh-keygen cannot make one.
ssh_ok=0
if command -v ssh-keygen > /dev/null 2>&1 &&
  ssh-keygen -q -t ed25519 -N '' -f "$TMP/ssh-key" > /dev/null 2>&1; then
  ssh_ok=1
else
  echo "  note ssh-keygen unavailable or key generation failed - ssh-commit cases skipped"
fi

if [ "$ssh_ok" -eq 1 ]; then
  if git -C "$REPO" -c gpg.format=ssh -c user.signingkey="$TMP/ssh-key.pub" \
    -c commit.gpgsign=true commit -q --allow-empty -m "ssh work" 2> /dev/null; then
    SSH="$(git -C "$REPO" rev-parse HEAD)"

    # The key is listed: a good signature, and the gate must accept it.
    printf 'sig-test@example.com %s\n' "$(cut -d' ' -f1,2 "$TMP/ssh-key.pub")" > "$TMP/allowed_signers"
    git -C "$REPO" config gpg.ssh.allowedSignersFile "$TMP/allowed_signers"
    STATUS="$(git -C "$REPO" log -1 --format='%G?' "$SSH")"
    if [ "$STATUS" = "G" ]; then
      ok "listed ssh key reports G (status ${STATUS})"
    else
      no "listed ssh key reports G (status ${STATUS})"
    fi
    # SSH^..SSH: only the ssh commit, or the older unsigned commits in the
    # range would make the rejection case below pass for the wrong reason.
    expect_rc 0 "accepts an ssh commit from a listed key" \
      check_in_repo "$SSH^" "$SSH"

    # The key is not listed: good signature, unknown validity. This U must be
    # rejected - accepting it would pass a commit signed by any ssh key.
    : > "$TMP/allowed_signers"
    STATUS="$(git -C "$REPO" log -1 --format='%G?' "$SSH")"
    if [ "$STATUS" = "U" ]; then
      ok "unlisted ssh key reports U (status ${STATUS})"
    else
      no "unlisted ssh key reports U (status ${STATUS})"
    fi
    expect_rc 1 "rejects an ssh commit whose key is not listed" \
      check_in_repo "$SSH^" "$SSH"

    # The rejection must say why the U was fatal, not just report a status.
    OUT="$(check_in_repo "$SSH^" "$SSH" 2>&1 || true)"
    case "$OUT" in
      *"not listed in gpg.ssh.allowedSignersFile"*) ok "rejection names the unlisted ssh key" ;;
      *) no "rejection names the unlisted ssh key" ;;
    esac
  else
    no "can create an ssh-signed commit with the throwaway key"
  fi
fi

teardown
trap - EXIT

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

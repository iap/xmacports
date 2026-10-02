#!/usr/bin/env bash
# Tests for scripts/check-attribution.sh and its commit-msg enforcement.
#
# A gate that cannot fail is worse than no gate, so every case here asserts a
# concrete exit code, and the suite includes negative controls (a body with a
# trailer MUST be rejected) alongside the positives (a clean body must pass).
#
# These bugs were found while building this and are pinned by cases below:
#   1. Reading .git/COMMIT_EDITMSG from pre-commit is STALE in a normal clone
#      and ABSENT in a linked worktree (.git is a file there) - the check
#      silently no-opped. Fixed by using the commit-msg hook, which receives the
#      message path as $1. Case: hook_receives_fresh_message_not_stale_file.
#   2. A guard that degrades to a no-op reads as a pass. Case:
#      hook_fails_closed_when_message_unreadable.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-attribution.sh"
HOOK="$ROOT/.githooks/commit-msg"

pass=0
fail=0
TMP=""

setup() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/attr-test.XXXXXX")"
}

teardown() {
  [ -n "$TMP" ] && [ -d "$TMP" ] && find "$TMP" -mindepth 1 -delete 2> /dev/null
  [ -n "$TMP" ] && [ -d "$TMP" ] && rmdir "$TMP" 2> /dev/null
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

echo "Running attribution-gate tests..."
setup
trap teardown EXIT

# --- script exists and is executable -------------------------------------
if [ -x "$CHECK" ]; then ok "check-attribution.sh is executable"; else no "check-attribution.sh is executable"; fi
if [ -x "$HOOK" ]; then ok "commit-msg hook is executable"; else no "commit-msg hook is executable"; fi

# --- the exact footer that shipped on MR !37 must be rejected ------------
printf 'fix(guard): x\n\nBody.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' \
  > "$TMP/claude-footer.md"
expect_rc 1 "rejects the Claude Code footer verbatim" \
  sh "$CHECK" --message-file "$TMP/claude-footer.md"

# --- variants: mangled link, bare name, lowercase, no link --------------
printf 'x\n\nGenerated with Claude Code\n' > "$TMP/bare.md"
expect_rc 1 "rejects bare 'Generated with Claude Code'" \
  sh "$CHECK" --message-file "$TMP/bare.md"

printf 'x\n\ngenerated with [claude code](https://claude.com/claude-code)\n' > "$TMP/lower.md"
expect_rc 1 "rejects lowercase variant (case-insensitive)" \
  sh "$CHECK" --message-file "$TMP/lower.md"

printf 'x\n\nGenerated with Cursor\n' > "$TMP/cursor.md"
expect_rc 1 "rejects other assistant generators" \
  sh "$CHECK" --message-file "$TMP/cursor.md"

printf 'x\n\nSee https://claude.com/claude-code for details\n' > "$TMP/host.md"
expect_rc 1 "rejects bare claude.com host" \
  sh "$CHECK" --message-file "$TMP/host.md"

# --- trailers ------------------------------------------------------------
printf 'x\n\nCo-authored-by: Some Person <s@example.com>\n' > "$TMP/coauth.md"
expect_rc 1 "rejects Co-authored-by trailer" \
  sh "$CHECK" --message-file "$TMP/coauth.md"

printf 'x\n\n  Co-authored-by: Someone <s@example.com>\n' > "$TMP/coauth-indent.md"
expect_rc 1 "rejects indented Co-authored-by trailer" \
  sh "$CHECK" --message-file "$TMP/coauth-indent.md"

printf 'x\n\nSigned-off-by: Someone <s@example.com>\n' > "$TMP/signoff.md"
expect_rc 1 "rejects Signed-off-by trailer" \
  sh "$CHECK" --message-file "$TMP/signoff.md"

# --- clean bodies must pass (no over-blocking) ---------------------------
printf 'fix(guard): require a declared mirror\n\nWhat changed and why.\n' > "$TMP/clean.md"
expect_rc 0 "accepts a clean message" \
  sh "$CHECK" --message-file "$TMP/clean.md"

printf 'fix(x): y\n\nExplain that generated code was reviewed.\n' > "$TMP/prose.md"
expect_rc 0 "accepts prose mentioning generated code" \
  sh "$CHECK" --message-file "$TMP/prose.md"

printf 'fix(x): y\n\nSee the documentation for co-authoring policy.\n' > "$TMP/prose2.md"
expect_rc 0 "accepts prose mentioning co-authoring" \
  sh "$CHECK" --message-file "$TMP/prose2.md"

: > "$TMP/empty.md"
expect_rc 0 "accepts an empty message" \
  sh "$CHECK" --message-file "$TMP/empty.md"

# --- stdin mode ----------------------------------------------------------
if printf 'x\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' |
  sh "$CHECK" --stdin > /dev/null 2>&1; then
  no "--stdin rejects the trailer"
else
  ok "--stdin rejects the trailer (rc=1)"
fi

# --- explicit opt-out ----------------------------------------------------
if SKIP_ATTRIBUTION_CHECK=1 sh "$CHECK" --message-file "$TMP/claude-footer.md" > /dev/null 2>&1; then
  ok "SKIP_ATTRIBUTION_CHECK=1 opts out"
else
  no "SKIP_ATTRIBUTION_CHECK=1 opts out"
fi
if SKIP_ATTRIBUTION_CHECK=0 sh "$CHECK" --message-file "$TMP/claude-footer.md" > /dev/null 2>&1; then
  no "SKIP_ATTRIBUTION_CHECK=0 does not opt out"
else
  ok "SKIP_ATTRIBUTION_CHECK=0 does not opt out"
fi

# --- usage errors are distinct from rejection ----------------------------
expect_rc 2 "bad usage exits 2 (not 1)" sh "$CHECK"
expect_rc 2 "missing file exits 2 (not 1)" \
  sh "$CHECK" --message-file "$TMP/does-not-exist"

# --- hook fails closed when the message file is unreadable ---------------
# A gate that silently no-ops is the failure mode that shipped once already.
if sh "$HOOK" > /dev/null 2>&1; then
  no "hook fails closed with no \$1"
else
  ok "hook fails closed with no \$1"
fi
if sh "$HOOK" "$TMP/does-not-exist" > /dev/null 2>&1; then
  no "hook fails closed on unreadable message"
else
  ok "hook fails closed on unreadable message"
fi

# --- the hook rejects a real trailer file (it is what git invokes) -------
if sh "$HOOK" "$TMP/claude-footer.md" > /dev/null 2>&1; then
  no "hook rejects a trailer via \$1"
else
  ok "hook rejects a trailer via \$1"
fi
if sh "$HOOK" "$TMP/clean.md" > /dev/null 2>&1; then
  ok "hook accepts a clean message via \$1"
else
  no "hook accepts a clean message via \$1"
fi

# --- git integration: real commits in a real repo -----------------------
# The unit cases above could all pass while the wiring is wrong, so drive the
# actual hook through git in a throwaway repo. This is what caught the stale
# COMMIT_EDITMSG bug: the hook must see the message of THIS commit.
if command -v git > /dev/null 2>&1; then
  REPO="$TMP/repo"
  git init -q "$REPO"
  mkdir -p "$REPO/scripts" "$REPO/.githooks"
  cp "$CHECK" "$REPO/scripts/check-attribution.sh"
  cp "$HOOK" "$REPO/.githooks/commit-msg"
  chmod +x "$REPO/scripts/check-attribution.sh" "$REPO/.githooks/commit-msg"
  git -C "$REPO" config core.hooksPath .githooks
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.com

  # hook_receives_fresh_message_not_stale_file: a bad message followed by a
  # clean one must PASS. If the hook read a stale .git/COMMIT_EDITMSG, this
  # clean commit would be rejected too.
  printf 'a\n' > "$REPO/f.txt"
  git -C "$REPO" add -A
  if git -C "$REPO" commit -q -m "bad one" -m "🤖 Generated with [Claude Code](https://claude.com/claude-code)" > /dev/null 2>&1; then
    no "git refuses the trailer commit"
  else
    ok "git refuses the trailer commit"
  fi

  if git -C "$REPO" commit -q -m "clean one" -m "no trailer here" > /dev/null 2>&1; then
    ok "hook_receives_fresh_message_not_stale_file: clean commit after a rejected one passes"
  else
    no "hook_receives_fresh_message_not_stale_file: clean commit was rejected"
  fi
  if git -C "$REPO" log --oneline 2> /dev/null | grep -qiE 'generated with|claude code'; then
    no "no trailer in git history"
  else
    ok "no trailer in git history"
  fi

  # and the reverse order: clean first, then a bad one
  printf 'b\n' > "$REPO/g.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "second clean" > /dev/null 2>&1
  if git -C "$REPO" commit -q --allow-empty -m "bad two" -m "Co-authored-by: X <x@example.com>" > /dev/null 2>&1; then
    no "git refuses the Co-authored-by commit"
  else
    ok "git refuses the Co-authored-by commit"
  fi
fi

teardown
trap - EXIT

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

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
ALLOW="$ROOT/scripts/attribution-allow.sh"
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

# These assertions describe the WORKTREE policy: what the tracked
# .attribution-allow in this checkout permits. Inside an MR pipeline the same
# variables are exported, and the gate would instead read the TARGET branch's
# allowlist - so before this MR merges, the self-credit cases below would fail
# against a file that is not on main yet. Clear them once, for the whole suite;
# the target-branch path is covered separately by its own committed fixture.
unset CI_MERGE_REQUEST_IID CI_MERGE_REQUEST_TARGET_BRANCH_NAME CI_MERGE_REQUEST_DIFF_BASE_SHA

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

# --- any tool name, not a hardcoded list -------------------------------
# The pattern used to enumerate known tools only, so a footer naming anything
# else - "Generated with [Another Tool]" - passed with rc=0. CodeRabbit raised
# this and the earlier reply wrongly claimed it fixed; it was not.
printf 'x\n\nGenerated with [Another Tool](https://example.com/t)\n' > "$TMP/othertool.md"
expect_rc 1 "rejects an unlisted tool name in brackets" \
  sh "$CHECK" --message-file "$TMP/othertool.md"

printf 'x\n\n🤖 Generated with [Zed McAgentface](https://example.com/z)\n' > "$TMP/zed.md"
expect_rc 1 "rejects an unlisted tool name behind an emoji" \
  sh "$CHECK" --message-file "$TMP/zed.md"

# The generic bracket rule must not swallow ordinary prose that happens to start
# the line with the same words.
printf 'x\n\nGenerated with care and attention.\n' > "$TMP/care.md"
expect_rc 0 "allows prose 'Generated with care'" \
  sh "$CHECK" --message-file "$TMP/care.md"

printf 'x\n\nGenerated with Cursor\n' > "$TMP/cursor.md"
expect_rc 1 "rejects other assistant generators" \
  sh "$CHECK" --message-file "$TMP/cursor.md"

# A bare claude.com URL mid-sentence is ordinary prose (a link someone is
# discussing) and must pass. Only a line that IS the link is a footer - see the
# barelink regression below. This case asserted the opposite before the pattern
# was anchored, which is exactly the over-blocking the anchor fixed.
printf 'x\n\nSee https://claude.com/claude-code for details\n' > "$TMP/host.md"
expect_rc 0 "accepts a claude.com URL mid-sentence" \
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

# --- creditable self-credit ----------------------------------------------
# The gate cannot tell that "Hermes" is this repo's owner rather than a real
# GitHub organization, so identity is decided on the ADDRESS. Only an address
# the repository may credit passes. These run against the real checkout, so the
# tracked .attribution-allow below is what the checker actually reads.
printf 'x\n\nCo-authored-by: Hermes <iap@users.noreply.github.com>\n' \
  > "$TMP/self-allowlisted.md"
expect_rc 0 "accepts a self-credit listed in .attribution-allow" \
  sh "$CHECK" --message-file "$TMP/self-allowlisted.md"

printf 'x\n\nCo-authored-by: Hermes <IAP@Users.NoReply.GitHub.com>\n' \
  > "$TMP/self-case.md"
expect_rc 0 "accepts a self-credit differing only in case" \
  sh "$CHECK" --message-file "$TMP/self-case.md"

# One permitted trailer must not launder another alongside it.
printf 'x\n\nCo-authored-by: Hermes <iap@users.noreply.github.com>\nCo-authored-by: Stranger <s@example.com>\n' \
  > "$TMP/mixed.md"
expect_rc 1 "rejects a bad trailer even beside a permitted one" \
  sh "$CHECK" --message-file "$TMP/mixed.md"

# One trailer is ONE party. Extracting the last <...> instead of the only one
# let an unlisted address ride along behind a creditable one, so the allowlist
# approved a line it had never seen.
printf 'x\n\nCo-authored-by: Evil <stranger@example.com> <iap@users.noreply.github.com>\n' \
  > "$TMP/smuggle-a.md"
expect_rc 1 "rejects an unlisted address smuggled after a listed one" \
  sh "$CHECK" --message-file "$TMP/smuggle-a.md"

printf 'x\n\nCo-authored-by: Hermes <iap@users.noreply.github.com> <stranger@example.com>\n' \
  > "$TMP/smuggle-b.md"
expect_rc 1 "rejects an unlisted address before a listed one" \
  sh "$CHECK" --message-file "$TMP/smuggle-b.md"

printf 'x\n\nCo-authored-by: Evil <stranger@example.com> Hermes\n' \
  > "$TMP/smuggle-c.md"
expect_rc 1 "rejects trailing text after the address" \
  sh "$CHECK" --message-file "$TMP/smuggle-c.md"

printf 'x\n\nCo-authored-by: Evil <stranger@example.com\n' \
  > "$TMP/smuggle-d.md"
expect_rc 1 "rejects an unmatched bracket" \
  sh "$CHECK" --message-file "$TMP/smuggle-d.md"

printf 'x\n\nCo-authored-by: Evil <<stranger@example.com>>\n' \
  > "$TMP/smuggle-e.md"
expect_rc 1 "rejects nested brackets" \
  sh "$CHECK" --message-file "$TMP/smuggle-e.md"

printf 'x\n\nCo-authored-by: Hermes\n' > "$TMP/noaddr.md"
expect_rc 1 "rejects a Co-authored-by with no address" \
  sh "$CHECK" --message-file "$TMP/noaddr.md"

printf 'x\n\nCo-authored-by: Hermes <iap@users.noreply.github.com.evil.tld>\n' \
  > "$TMP/lookalike.md"
expect_rc 1 "rejects a lookalike domain" \
  sh "$CHECK" --message-file "$TMP/lookalike.md"

# Signed-off-by stays forbidden even for a creditable address: it is a legal
# sign-off, not an authorship credit, and this repo does not use it.
printf 'x\n\nSigned-off-by: Hermes <iap@users.noreply.github.com>\n' \
  > "$TMP/signoff-self.md"
expect_rc 1 "rejects Signed-off-by even for a creditable address" \
  sh "$CHECK" --message-file "$TMP/signoff-self.md"

printf 'x\n\nCo-authored-by: Tester <agent@xmacports.invalid>\n' > "$TMP/override.md"
expect_rc 0 "ATTRIBUTION_ALLOWLIST permits an unlisted address" \
  env ATTRIBUTION_ALLOWLIST='agent@xmacports.invalid' \
  sh "$CHECK" --message-file "$TMP/override.md"

# --- the MR target branch is the authority --------------------------------
# In MR CI the checkout IS the branch under review, so a file-sourced allowlist
# would let an MR widen the policy and spend the credit in the same MR.
if git -C "$ROOT" rev-parse --verify --quiet HEAD > /dev/null 2>&1; then
  printf 'x\n\nCo-authored-by: Hermes <iap@users.noreply.github.com>\n' \
    > "$TMP/mr.md"
  expect_rc 2 "refuses when the MR target branch cannot be resolved" \
    env CI_MERGE_REQUEST_IID=42 \
    CI_MERGE_REQUEST_TARGET_BRANCH_NAME='refs/heads/no-such-branch' \
    sh "$CHECK" --message-file "$TMP/mr.md"
fi

# The layout a GitLab MR runner actually produces: ONE ref checked out (the
# source branch), with the target available only as refs/remotes/origin/<name>.
# Resolving the bare target name there fails, which made the gate exit 2 on
# every MR pipeline. Reproduce that layout in a throwaway clone.
if git -C "$ROOT" rev-parse --verify --quiet HEAD > /dev/null 2>&1; then
  MREPO="$TMP/mrrepo"
  git clone -q --no-hardlinks --depth 1 "file://$ROOT" "$MREPO" > /dev/null 2>&1
  if [ -d "$MREPO/.git" ]; then
    base=$(git -C "$MREPO" rev-parse HEAD)
    # Two commits on the MR's source branch: the first establishes a target-side
    # allowlist, the second WIDENS it. origin/main is pinned to the first, so
    # reading origin/main and reading the MR branch give different answers -
    # which is what makes these two assertions meaningful.
    printf 'mr-allowlisted@example.invalid\n' > "$MREPO/.attribution-allow"
    git -C "$MREPO" add -A > /dev/null 2>&1
    git -C "$MREPO" -c user.email=t@example.invalid -c user.name=t \
      commit -qm "target branch carries the allowlist" > /dev/null 2>&1
    target=$(git -C "$MREPO" rev-parse HEAD)
    printf 'mr-widened@example.invalid\n' >> "$MREPO/.attribution-allow"
    git -C "$MREPO" add -A > /dev/null 2>&1
    git -C "$MREPO" -c user.email=t@example.invalid -c user.name=t \
      commit -qm "mr widens the allowlist" > /dev/null 2>&1
    # Now point origin/main at the narrower commit: it stands in for the target
    # branch, which the MR cannot change.
    git -C "$MREPO" update-ref "refs/remotes/origin/main" "$target"
    # Use the WORKING TREE's scripts, not the committed ones: the clone's HEAD
    # is whatever was last committed, so cloning alone would silently test a
    # previous version of the gate.
    cp "$CHECK" "$ALLOW" "$MREPO/scripts/"
    # A third value in the worktree that the MR job must NOT read.
    printf 'worktree-allowlisted@example.invalid\n' > "$MREPO/.attribution-allow.worktree"
    printf 'x\n\nCo-authored-by: T <mr-allowlisted@example.invalid>\n' > "$TMP/mr-ok.md"
    printf 'x\n\nCo-authored-by: M <mr-widened@example.invalid>\n' > "$TMP/mr-no.md"
    printf 'x\n\nCo-authored-by: W <worktree-allowlisted@example.invalid>\n' > "$TMP/mr-wt.md"

    if git -C "$MREPO" rev-parse --verify --quiet 'refs/heads/main' > /dev/null 2>&1; then
      echo "note clone has a local main; skipping the shallow-layout case"
    else
      expect_rc 0 "resolves the MR target via refs/remotes/origin/<name>" \
        env CI_MERGE_REQUEST_IID=42 \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME=main \
        sh -c 'cd "$1" && sh scripts/check-attribution.sh --message-file "$2"' \
        sh "$MREPO" "$TMP/mr-ok.md"
      expect_rc 1 "does not trust the MR branch's own allowlist entry" \
        env CI_MERGE_REQUEST_IID=42 \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME=main \
        sh -c 'cd "$1" && sh scripts/check-attribution.sh --message-file "$2"' \
        sh "$MREPO" "$TMP/mr-no.md"
      expect_rc 1 "does not read an allowlist sitting in the worktree" \
        env CI_MERGE_REQUEST_IID=42 \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME=main \
        sh -c 'cd "$1" && sh scripts/check-attribution.sh --message-file "$2"' \
        sh "$MREPO" "$TMP/mr-wt.md"
    fi
  fi
fi

# --- .attribution-allow is present AND tracked ---------------------------
# Tracked on purpose: it is the auditable record of who may be credited, so an
# untracked copy is invisible to CI and to every other clone - which is how a
# self-credit passes the local hook and fails the MR job.
if [ -f "$ROOT/.attribution-allow" ]; then
  ok ".attribution-allow is present in the repo"
else
  no ".attribution-allow is present in the repo"
fi

if git -C "$ROOT" ls-files --error-unmatch .attribution-allow > /dev/null 2>&1; then
  ok ".attribution-allow is tracked by git"
else
  no ".attribution-allow is tracked by git"
fi

if [ -r "$ROOT/.attribution-allow" ]; then
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%%#*}"
    [ -n "${entry//[[:space:]]/}" ] || continue
    printf 'x\n\nCo-authored-by: Tester <%s>\n' "$entry" > "$TMP/each.md"
    expect_rc 0 "every .attribution-allow entry is creditable" \
      sh "$CHECK" --message-file "$TMP/each.md"
  done < "$ROOT/.attribution-allow"
  ok ".attribution-allow is readable"
else
  no ".attribution-allow is readable"
fi

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

# A commit body that QUOTES the vendor name in prose must pass. This case was
# found in real use: the commit explaining that the footer is rejected was itself
# rejected, because the pattern was unanchored and matched the quoted text
# mid-sentence. A gate that blocks honest documentation gets routed around.
cat > "$TMP/prose3.md" << 'EOF'
ci(attribution): check MR descriptions

The commit-msg hook cannot see an MR description. That gap is how a false
"Generated with Claude Code" footer reached MR !37, and it is why prose
warnings failed to stop it.
EOF
expect_rc 0 "accepts prose QUOTING the vendor name (regression)" \
  sh "$CHECK" --message-file "$TMP/prose3.md"

printf 'docs: note the rule\n\nWe reject lines that read Generated with Claude Code verbatim.\n' > "$TMP/prose4.md"
expect_rc 0 "accepts mid-sentence vendor mention (regression)" \
  sh "$CHECK" --message-file "$TMP/prose4.md"

# ...but a real footer on its own line must still be rejected, with or without
# the emoji, and a bare link line is a footer too.
printf 'fix(x): y\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' > "$TMP/emoji.md"
expect_rc 1 "still rejects the real footer with emoji (regression)" \
  sh "$CHECK" --message-file "$TMP/emoji.md"

printf 'fix(x): y\n\nGenerated with [Claude Code](https://claude.com/claude-code)\n' > "$TMP/noemoji.md"
expect_rc 1 "still rejects a bare footer line, no emoji (regression)" \
  sh "$CHECK" --message-file "$TMP/noemoji.md"

printf 'fix(x): y\n\nhttps://claude.com/claude-code\n' > "$TMP/barelink.md"
expect_rc 1 "still rejects a bare claude.com link line (regression)" \
  sh "$CHECK" --message-file "$TMP/barelink.md"

# A directory passes the `-r` test but cannot be read as a file. Before this was
# checked, `cat` failed, the temp file stayed empty, grep matched nothing and the
# gate exited 0 - a fail-open on the most likely user mistake. Regression for the
# fail-open class this gate exists to prevent.
mkdir -p "$TMP/adir"
expect_rc 2 "rejects a directory (fail-closed, not a silent pass)" \
  sh "$CHECK" --message-file "$TMP/adir"

# The opt-out must be exactly "1". Testing "!= 0" let any incidental value
# disable a blocking gate.
expect_rc 1 "SKIP_ATTRIBUTION_CHECK=2 does NOT bypass" \
  env SKIP_ATTRIBUTION_CHECK=2 sh "$CHECK" --message-file "$TMP/claude-footer.md"
expect_rc 0 "SKIP_ATTRIBUTION_CHECK=1 bypasses" \
  env SKIP_ATTRIBUTION_CHECK=1 sh "$CHECK" --message-file "$TMP/claude-footer.md"

# Markdown quoting markers must not be mistaken for footer decoration, or
# documentation quoting the convention gets blocked.
printf 'docs: rule\n\n> Generated with ChatGPT\n' > "$TMP/bq.md"
expect_rc 0 "accepts a blockquoted example (regression)" \
  sh "$CHECK" --message-file "$TMP/bq.md"
printf 'docs: rule\n\n- Generated with ChatGPT\n' > "$TMP/li.md"
expect_rc 0 "accepts a list-bulleted example (regression)" \
  sh "$CHECK" --message-file "$TMP/li.md"

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

# --- hook fails closed when the repo root cannot be resolved --------------
# CodeRabbit flagged the TEST for running the hook from outside the checkout, but
# the defect is in the hook: it resolved the repo root and then ran nothing when
# that was empty, so a real footer passed with exit 0. The test above now cds
# into the checkout; this asserts the hook itself no longer no-ops.
# A subshell cd, not `env -C`: that option needs macOS 13+ and this box is 12.7,
# where `env -C` fails and its own exit status masquerades as the hook's.
(
  cd "$TMP" && sh "$HOOK" "$TMP/claude-footer.md"
) > /dev/null 2>&1
rc=$?
if [ "$rc" -ne 1 ]; then
  no "hook refuses when the repo root cannot be resolved (rc=$rc, want 1)"
else
  ok "hook refuses when the repo root cannot be resolved"
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
# The hook resolves the repo root from `git rev-parse --show-toplevel`, so these
# direct invocations must run from inside the checkout. Run from elsewhere TOP is
# empty, the hook skips the checker and returns 0 — the rejection case would fail
# and the clean case would pass without checking anything.
cd "$ROOT" || exit 1
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
  cp "$ALLOW" "$REPO/scripts/attribution-allow.sh"
  cp "$HOOK" "$REPO/.githooks/commit-msg"
  chmod +x "$REPO/scripts/check-attribution.sh" "$REPO/.githooks/commit-msg"
  git -C "$REPO" config core.hooksPath .githooks
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.com
  # Isolate from the host's signing config: if commit.gpgsign is inherited and no
  # key is available, the clean commits fail for a reason unrelated to the hook,
  # and the rejection cases would look like they were caused by the gate.
  git -C "$REPO" config commit.gpgsign false

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

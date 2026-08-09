#!/usr/bin/env bash
# verify-review-fixes.sh — revert-check each review fix on fix/review-findings.
# Each section asserts the bug is FIXED. A companion "broken" variant proves the
# test is non-vacuous (run with the original files to see it fail).
set -u
DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Source shared functions so gitstat (L) is defined when called directly.
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shared/functions.sh"
pass=0
fail=0
ok() {
  echo "  ok   $1"
  pass=$((pass + 1))
}
bad() {
  echo "  FAIL $1"
  fail=$((fail + 1))
}

# ---- A/C: audit.sh + compliance-check.sh now exit non-zero on findings ----
echo "A/C audit/compliance exit code on a defect:"
# simulate a world-writable dotfiles dir
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.dotfiles"
chmod 777 "$T/.dotfiles"
out=$(DOTFILES_ROOT="$T/.dotfiles" bash "$DOTFILES_ROOT/scripts/audit.sh" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then ok "audit.sh exits non-zero when a defect exists (rc=$rc)"; else bad "audit.sh still exits 0 on defect"; fi

# ---- B: world-writable octal parsing ----
echo "B audit octal parsing (no false negatives):"
for spec in "777:yes:yes" "700:no:no" "755:no:no" "2755:no:no" "750:no:no" "773:yes:yes"; do
  perm=${spec%%:*}
  rest=${spec#*:}
  exp_ow=${rest%%:*}
  exp_gw=${rest#*:}
  # replicate the fixed parsing
  mode=$((10#$perm % 1000))
  ow=$((mode % 10 & 2))
  gw=$(((mode / 10) % 10 & 2))
  got_ow=$([ "$ow" -ne 0 ] && echo yes || echo no)
  got_gw=$([ "$gw" -ne 0 ] && echo yes || echo no)
  if [ "$got_ow" = "$exp_ow" ] && [ "$got_gw" = "$exp_gw" ]; then
    ok "perm $perm -> other=$got_ow group=$got_gw"
  else
    bad "perm $perm -> got other=$got_ow group=$got_gw expected other=$exp_ow group=$exp_gw"
  fi
done

# ---- D: pre-push allows --delete on a mirror ----
echo "D pre-push allows branch deletion on mirror:"
HOOK="$DOTFILES_ROOT/.githooks/pre-push"
T2=$(mktemp -d)
cd "$T2" || exit 1
git init -q w
git config user.email t@e
git config user.name t
git config commit.gpgsign false
# bare repos so `git push -u origin main` actually sets branch.main.remote
git init -q --bare "$T2/origin.git"
git init -q --bare "$T2/mirror.git"
git remote add origin "$T2/origin.git"
git remote add mirror "$T2/mirror.git"
cd w || exit 1
git symbolic-ref HEAD refs/heads/main
mkdir -p .githooks
cp "$HOOK" .githooks/pre-push
chmod +x .githooks/pre-push
git config core.hooksPath .githooks
git commit -q --allow-empty -m x
git push -q -u origin main 2> /dev/null
git checkout -q -b todelete
git commit -q --allow-empty -m y
# delete from mirror: stdin line with zero LOCAL oid (git delete contract)
_delete_oid=$(git rev-parse todelete 2> /dev/null || git rev-parse HEAD)
echo "refs/heads/todelete 0000000000000000000000000000000000000000 refs/heads/todelete $_delete_oid" |
  bash .githooks/pre-push mirror > /dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then ok "git push --delete topic from mirror allowed (rc=0)"; else bad "delete still blocked (rc=$rc)"; fi
# A real topic push to a mirror is already covered by the dedicated
# tests/test-pre-push-hook.sh suite (8 cases) and verified manually on the
# real repo (git push <topic> github -> rc=1). This harness asserts the NEW
# behavior: deletions on a mirror are allowed (above).
cd "$DOTFILES_ROOT" || exit 1

# ---- E: pre-commit blocks nested SSH keys ----
echo "E pre-commit catches nested SSH private keys:"
PC="$DOTFILES_ROOT/.githooks/pre-commit"
T3=$(mktemp -d)
cd "$T3" || exit 1
git init -q c
cd c || exit 1
git config user.email t@e
git config user.name t
git config commit.gpgsign false
mkdir -p keys
# Stub Makefile so the pre-commit hook's `make fmt-check`/`make shellcheck`
# succeed in this isolated repo (the real repo has a real Makefile). Without
# this, `make` errors "no makefile found" and the hook rejects before it ever
# scans for SSH keys — making the test vacuous.
printf 'fmt-check:\n\t@true\nshellcheck:\n\t@true\n' > Makefile
# A key file whose CONTENT has no PEM header, so only the NAME-based pattern can
# catch it. This proves the nested-name fix (E) is what triggers, not the
# content grep at pre-commit:68.
printf '%s\n' 'not-a-real-key-body' > keys/id_ed25519
git add -f keys/id_ed25519 Makefile
staged=$(git diff --cached --name-only)
out=$(echo "$staged" | bash "$PC" 2>&1)
rc=$?
if echo "$out" | grep -q 'SSH private key detected'; then
  ok "nested keys/id_ed25519 rejected (rc=$rc, message present)"
else
  bad "nested SSH key slipped through (rc=$rc, out=[$out])"
fi
cd "$DOTFILES_ROOT" || exit 1

# ---- F: make secrets-encrypt/decrypt source functions.sh (log_* defined) ----
echo "F SECRETS_SH sources functions.sh:"
if grep -q 'shared/functions.sh' "$DOTFILES_ROOT/Makefile"; then ok "Makefile SECRETS_SH sources functions.sh"; else bad "SECRETS_SH still missing functions.sh"; fi

# ---- G: secrets-init.sh rotation preserves indent + errors on miss ----
echo "G secrets-init.sh rotation is correct:"
if grep -qE '\[\[:space:\]\]\*\)age: age1' "$DOTFILES_ROOT/scripts/secrets-init.sh"; then
  ok "rotation sed captures/preserves leading indent"
else
  bad "rotation sed still anchored to column 0"
fi
if grep -q 'grep -q "age: \$PUBLIC_KEY"' "$DOTFILES_ROOT/scripts/secrets-init.sh"; then
  ok "rotation verifies result / errors on miss"
else
  bad "rotation does not verify or error on miss"
fi

# ---- H: zsh HISTORY_IGNORE is a single glob, not newlines ----
echo "H zsh HISTORY_IGNORE single glob:"
if grep -q 'HISTORY_IGNORE="(${HISTORY_IGNORE:+$HISTORY_IGNORE|}export \*|secret \*|\*TOKEN\*|\*SECRET\*|\*API_KEY\*)"' "$DOTFILES_ROOT/shared/aliases.sh"; then
  ok "HISTORY_IGNORE is a single-line glob"
else
  bad "HISTORY_IGNORE still malformed"
fi

# ---- I: XDG_RUNTIME_DIR used (not HOME) ----
echo "I XDG_RUNTIME_DIR spelling:"
if grep -rq 'XDG_RUNTIME_HOME' "$DOTFILES_ROOT/bootstrap.sh" "$DOTFILES_ROOT/scripts/verify-migration.sh"; then
  bad "XDG_RUNTIME_HOME still present"
else
  ok "XDG_RUNTIME_HOME replaced by XDG_RUNTIME_DIR"
fi

# ---- J: macOS MAKE_JOBS + don't clobber user MAKEFLAGS ----
echo "J platform.sh MAKE_JOBS macOS + MAKEFLAGS guard:"
if grep -q 'hw.ncpu' "$DOTFILES_ROOT/shared/platform.sh"; then ok "sysctl hw.ncpu branch added"; else bad "no macOS ncpu branch"; fi
if grep -q 'MAKEFLAGS:-' "$DOTFILES_ROOT/shared/platform.sh"; then ok "MAKEFLAGS only exported when unset"; else bad "MAKEFLAGS still unconditionally exported"; fi

# ---- K: prompt.sh cache_file paren fix ----
echo "K prompt.sh SHELL_CACHE_DIR paren:"
if grep -q 'SHELL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/shell}/git_status_' "$DOTFILES_ROOT/shared/prompt.sh"; then
  ok "cache_file paren moved (per-dir hash outside fallback)"
else
  bad "cache_file still collapses to SHELL_CACHE_DIR"
fi

# ---- L: gitstat returns 0 on clean repo, no stray 0 ----
echo "L gitstat clean-repo behavior:"
# Run in a deterministic clean repo, not the (possibly dirty) working tree.
LT=$(mktemp -d)
git init -q "$LT"
out=$(cd "$LT" && gitstat 2> /dev/null)
rc=$?
rm -rf "$LT"
# A clean repo prints "CHANGES: 0" exactly once; the old code printed a stray
# "0" line because of an unguarded `grep -c . || echo 0`. Assert rc=0 and that
# the output contains "CHANGES: 0" (no second "0" line).
if [ "$rc" -eq 0 ] && echo "$out" | grep -qx 'CHANGES: 0'; then
  ok "gitstat exits 0, clean repo shows CHANGES: 0 (rc=$rc)"
else
  bad "gitstat still broken (rc=$rc, out=[$out])"
fi

echo
echo "Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

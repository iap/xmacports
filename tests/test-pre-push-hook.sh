#!/bin/bash
# Regression tests for .githooks/pre-push.
#
# Verifies the hook blocks topic-branch pushes to a non-authoritative (mirror)
# remote while leaving every legitimate push untouched. Uses local bare repos
# as remotes, so it needs no network.
#
# Guards the 2026-08 incident: a topic branch was pushed to the GitHub mirror
# while `main` tracked GitLab.

set -uo pipefail

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$DOTFILES_ROOT/.githooks/pre-push"

pass=0
fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "  ✅ $1"
    pass=$((pass + 1))
  else
    echo "  ❌ $1 (expected exit $2, got $3)"
    fail=$((fail + 1))
  fi
}

if [ ! -x "$HOOK" ]; then
  echo "❌ .githooks/pre-push missing or not executable"
  exit 1
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1

setup_repo() { # dir; extra remotes configured by caller
  git init -q "$1" && cd "$1" || exit 1
  git config user.email test@example.com
  git config user.name test
  git config commit.gpgsign false
  # git's default branch name varies by version/platform (main vs master), and
  # the hook resolves it dynamically — pin it here so the test is deterministic.
  git symbolic-ref HEAD refs/heads/main
  mkdir -p .githooks
  cp "$HOOK" .githooks/pre-push
  chmod +x .githooks/pre-push
  git config core.hooksPath .githooks
}

git init -q --bare authoritative.git
git init -q --bare mirror.git
git init -q --bare only.git

# --- Mirror topology: main tracks origin, `mirror` is a second remote --------
setup_repo work
git remote add origin "$T/authoritative.git"
git remote add mirror "$T/mirror.git"
git commit -q --allow-empty -m init
git push -q -u origin main 2> /dev/null
git checkout -q -b topic/x
git commit -q --allow-empty -m work

echo "Pre-push hook — mirror topology:"
git push mirror topic/x > /dev/null 2>&1
check "topic branch to mirror is blocked" 1 $?
git push origin topic/x > /dev/null 2>&1
check "topic branch to authoritative remote is allowed" 0 $?
git checkout -q main
git push mirror main > /dev/null 2>&1
check "default branch to mirror is allowed" 0 $?
git tag -f v1 -m t > /dev/null 2>&1
git push mirror v1 > /dev/null 2>&1
check "tag to mirror is allowed" 0 $?
git checkout -q topic/x
git push --no-verify mirror topic/x > /dev/null 2>&1
check "--no-verify bypasses the hook" 0 $?
git push "$T/mirror.git" topic/x > /dev/null 2>&1
check "push by URL is not blocked" 0 $?

# --- Single remote: hook must be inert --------------------------------------
cd "$T" || exit 1
setup_repo solo
git remote add origin "$T/only.git"
git commit -q --allow-empty -m init
git push -q -u origin main 2> /dev/null
git checkout -q -b feat/y
git commit -q --allow-empty -m work

echo "Pre-push hook — single remote:"
git push origin feat/y > /dev/null 2>&1
check "topic branch to the only remote is allowed" 0 $?

# --- Two remotes but no authoritative tracking: must not block --------------
cd "$T" || exit 1
setup_repo notrack
git remote add origin "$T/authoritative.git"
git remote add other "$T/mirror.git"
git commit -q --allow-empty -m init
git checkout -q -b topic/z
git commit -q --allow-empty -m work

echo "Pre-push hook — unresolvable topology:"
git push other topic/z > /dev/null 2>&1
check "no false block when no default branch tracks a remote" 0 $?

echo
echo "Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

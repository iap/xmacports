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
GUARD="$(cd "$(dirname "$HOOK")/.." && pwd)/scripts/guard-default-branch"

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
  mkdir -p .githooks scripts
  cp "$HOOK" .githooks/pre-push
  chmod +x .githooks/pre-push
  # The default-branch guard is a SEPARATE program invoked by the hook. Without
  # it here the hook takes the "guard not found" path, and every test below would
  # pass while the guard was never exercised at all.
  cp "$GUARD" scripts/guard-default-branch
  chmod +x scripts/guard-default-branch
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
git push -q --no-verify -u origin main 2> /dev/null
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
# A URL/path push still hits the topic-branch policy: anything that is not the
# authoritative remote is refused. Push a NEW commit first, because pushing an
# up-to-date ref sends an empty pre-push ref list, so the hook never evaluates
# it and the check would pass vacuously.
git commit -q --allow-empty -m url-push
git push "$T/mirror.git" topic/x > /dev/null 2>&1
check "topic branch pushed by URL to a mirror is blocked" 1 $?

# --- Single remote: hook must be inert --------------------------------------
cd "$T" || exit 1
setup_repo solo
git remote add origin "$T/only.git"
git commit -q --allow-empty -m init
git push -q --no-verify -u origin main 2> /dev/null
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

# --- Default-branch guard -----------------------------------------------------
# These only pass when scripts/guard-default-branch is present AND enforcing.

setup_repo guardwork
git remote add origin "$T/authoritative.git"
git commit -q --allow-empty -m init
# Seed with --no-verify: the FIRST push of the default branch is itself "create
# main", which the guard refuses by design. Pushing it through the hook would
# leave branch.main.remote unset, and every check below would then run against a
# repo with no authoritative remote - passing or failing for the wrong reason.
git push -q --no-verify origin main 2> /dev/null
git config branch.main.remote origin
git config branch.main.merge refs/heads/main
git fetch -q origin 2> /dev/null
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2> /dev/null

# A mirror remote, so the mirror cases are exercised alongside the guard ones.
git init -q --bare "$T/guard-mirror.git"
git remote add mirror "$T/guard-mirror.git"

echo "Pre-push hook — default-branch guard:"

git commit -q --allow-empty -m direct
git push origin main > /dev/null 2>&1
check "direct push to the default branch is blocked" 1 $?

# The guard prefers the remote the CURRENT branch tracks, read from that
# branch's own git key. A branch name containing "/" used to be truncated to its
# last segment first, so on branch feat/x it consulted branch.x.remote instead of
# branch.feat/x.remote, found nothing, and fell back to origin. With origin not
# the authoritative remote, the authoritative remote was then classified a
# mirror, and mirrors are exempt from the default-branch rule - so a push to the
# default branch was allowed. On the unfixed guard this case exits 0.
slashed_guard() {
  local d="$T/slash"
  mkdir -p "$d"
  git init -q --bare "$d/upstream.git"
  git init -q --bare "$d/mirror.git"
  git init -q "$d/w"
  (
    cd "$d/w" || exit 1
    git config user.email t@example.com
    git config user.name T
    git config commit.gpgsign false
    git remote add upstream "$d/upstream.git"
    git remote add mirror "$d/mirror.git"
    echo a > f
    git add f
    git commit -qm one
    git branch -M main
    git push -q upstream main
    git push -q mirror main
    git --git-dir="$d/upstream.git" symbolic-ref HEAD refs/heads/main
    git remote set-head upstream -a > /dev/null 2>&1
    git checkout -qB feat/x
    git config branch.feat/x.remote upstream
    # Authority must be undetermined for the mirror exemption to be reachable.
    git config --unset branch.main.remote 2> /dev/null || true
    git checkout -q main
    git commit -q --allow-empty -m diverge
    git checkout -q feat/x
  )
  printf 'refs/heads/feat/x %s refs/heads/main %s\n' \
    "$(cd "$d/w" && git rev-parse refs/heads/main)" \
    "$(git --git-dir="$d/upstream.git" rev-parse refs/heads/main)" > "$d/lines"
  (
    cd "$d/w" || exit 1
    sh "$GUARD" "$d/lines" upstream > "$d/out" 2>&1
  )
}

slashed_guard
check "default branch push from a slashed branch name is blocked" 1 $?
rm -rf "$T/slash"

git push origin :main > /dev/null 2>&1
check "deleting the default branch is blocked" 1 $?

# A push by local PATH must be judged the same as one by remote name: the guard
# has to resolve the path back to the remote or the rule is silently skipped.
git commit -q --allow-empty -m via-path
git push "$T/authoritative.git" main > /dev/null 2>&1
check "direct push by local path is blocked" 1 $?

# ...and the same for a URL-shaped argument.
git commit -q --allow-empty -m via-url
git push "file://$T/authoritative.git" main > /dev/null 2>&1
check "direct push by file:// URL is blocked" 1 $?

# A fast-forward topic push must still be allowed, or the guard is useless.
git checkout -q -b topic/ok
git commit -q --allow-empty -m work
git push -u origin topic/ok > /dev/null 2>&1
check "new topic branch is still allowed" 0 $?

git commit -q --allow-empty -m more
git push origin topic/ok > /dev/null 2>&1
check "fast-forward topic update is still allowed" 0 $?

# A force-pushed topic branch rewrites published history and must be refused.
git reset -q --hard HEAD~1
git commit -q --allow-empty -m divergent
git push --force origin topic/ok > /dev/null 2>&1
check "force-pushing a rewritten topic branch is blocked" 1 $?

# Mirror cases: the guard must stay out of the way. Syncing the default branch to
# a mirror is legitimate, and a topic branch must not go there - whether the target
# is named or given as a path.
#
# Each of these pushes for real, with the hook active. Pre-pushing with --no-verify
# would leave nothing to send and git would report success without the hook ever
# seeing a ref, so the assertion would be vacuous.
git commit -q --allow-empty -m mirror-sync
git push mirror main > /dev/null 2>&1
check "default branch to mirror is allowed" 0 $?

git push mirror topic/ok > /dev/null 2>&1
check "topic branch to mirror is blocked" 1 $?

git push "$T/guard-mirror.git" topic/ok > /dev/null 2>&1
check "topic branch to mirror by path is blocked" 1 $?

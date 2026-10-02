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

# --- Ambiguous authority: a mirror must be declared, not inferred ------------
# When the default branch tracks no remote, the guard cannot know which remote is
# authoritative, so it may not exempt any remote on a guess. It used to treat
# "not the current branch's tracking remote" as "is a mirror", which is a
# different question: that value records where a topic branch publishes. So a
# clone whose default branch tracked nothing could be pushed to directly, by
# naming any remote other than the current branch's own - the mirror exemption
# answered a question nobody asked.
#
# Each case below drives the guard directly, because the point is the guard's
# decision, not git's ability to push.
ambiguous_guard() { # tracking-remote; prints the exit code for a push to origin
  local d="$T/amb"
  mkdir -p "$d"
  git init -q --bare "$d/upstream.git"
  git init -q --bare "$d/mirror.git"
  git init -q "$d/w"
  (
    cd "$d/w" || exit 1
    git config user.email t@example.com
    git config user.name test
    git config commit.gpgsign false
    git remote add origin "$d/upstream.git"
    git remote add mirror "$d/mirror.git"
    echo a > f
    git add f
    git commit -qm one
    git branch -M main
    git push -q origin main
    git push -q mirror main
    # Both remotes know the default branch, so resolution cannot be blamed on
    # an unresolvable HEAD.
    git --git-dir="$d/upstream.git" symbolic-ref HEAD refs/heads/main
    git --git-dir="$d/mirror.git" symbolic-ref HEAD refs/heads/main
    git remote set-head origin -a > /dev/null 2>&1
    git checkout -qB "$1"
    # The topic branch tracks $1 while the DEFAULT branch tracks nothing: the
    # ambiguity this exploits is exactly that unset config.
    git config "branch.$1.remote" "$1"
    git config --unset branch.main.remote 2> /dev/null || true
    git checkout -q main
    git commit -q --allow-empty -m diverge
    git checkout -q "$1"
  )
  printf 'refs/heads/%s %s refs/heads/main %s\n' \
    "$1" \
    "$(cd "$d/w" && git rev-parse refs/heads/main)" \
    "$(git --git-dir="$d/upstream.git" rev-parse refs/heads/main)" > "$d/lines"
  # Run inside the clone: the guard resolves branch config from the cwd.
  (cd "$d/w" && sh "$GUARD" "$d/lines" origin > /dev/null 2>&1)
}

echo
echo "Pre-push hook — ambiguous authority (no default-branch tracking):"
ambiguous_guard foo
check "default branch push is blocked when a slashless branch tracks the mirror" 1 $?
rm -rf "$T/amb"

ambiguous_guard "feat/x"
check "default branch push is blocked when a slashed branch tracks the mirror" 1 $?
rm -rf "$T/amb"

# The exemption is still available, but only when stated.
ambiguous_guard foo
(
  cd "$T/amb/w" || exit 1
  git config remote.mirror.mirror true
)
(
  cd "$T/amb/w" && sh "$GUARD" "$T/amb/lines" mirror > /dev/null 2>&1
)
check "a remote declared a mirror is exempt even when authority is unknown" 0 $?
rm -rf "$T/amb"

# Declaring the wrong remote must not exempt the authoritative one.
ambiguous_guard foo
(
  cd "$T/amb/w" || exit 1
  git config remote.mirror.mirror true
)
(
  cd "$T/amb/w" && sh "$GUARD" "$T/amb/lines" origin > /dev/null 2>&1
)
check "declaring one remote a mirror does not exempt another" 1 $?
rm -rf "$T/amb"

# `git config --bool` normalises yes/on/1 to true, so the documented values all
# work. An unparseable value makes git exit non-zero with the error on stderr,
# which is discarded here, leaving nothing to compare against "true" - so it
# fails closed rather than exempting anything. Both properties are worth
# pinning, because the second is the one a reader would assume works.
mirror_flag_verdict() { # value; prints the guard's exit code for a push to mirror
  ambiguous_guard foo
  (
    cd "$T/amb/w" || exit 1
    [ -n "$1" ] && git config remote.mirror.mirror "$1"
  )
  (
    cd "$T/amb/w" && sh "$GUARD" "$T/amb/lines" mirror > /dev/null 2>&1
  )
}

mirror_flag_verdict yes
check "'yes' is accepted as a mirror" 0 $?
rm -rf "$T/amb"

mirror_flag_verdict garbage
check "an unparseable mirror value is not treated as a mirror" 1 $?
rm -rf "$T/amb"

echo
echo "Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

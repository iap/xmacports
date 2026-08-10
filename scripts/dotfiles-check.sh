#!/bin/sh
# dotfiles-check.sh — fail-silent upstream fetch + review.
# Intended to run at shell init (throttled). Prints nothing when up to date.
# Safe: never blocks login; all git/network errors are swallowed.

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$CACHE_DIR" 2>/dev/null

# Throttle: at most one network check per 30 minutes per machine.
THROTTLE=1800
STAMP="$CACHE_DIR/last-fetch-check"
NOW=$(date +%s)
LAST=0
[ -f "$STAMP" ] && LAST=$(cat "$STAMP" 2>/dev/null | tr -d '\n' | grep -E '^[0-9]+$' || echo 0)
if [ $((NOW - LAST)) -lt "$THROTTLE" ]; then
  exit 0
fi
echo "$NOW" > "$STAMP" 2>/dev/null

# Fail-silent fetch (git's own timeout kills a stalled SSH session).
git -C "$DOTFILES_ROOT" -c fetch.timeout=10 fetch origin --quiet 2>/dev/null || true

# Need an upstream to compare against.
UP=$(git -C "$DOTFILES_ROOT" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
[ -z "$UP" ] && exit 0

BEHIND=$(git -C "$DOTFILES_ROOT" rev-list --count HEAD...@{u} 2>/dev/null || echo 0)
AHEAD=$(git -C "$DOTFILES_ROOT" rev-list --count @{u}...HEAD 2>/dev/null || echo 0)

if [ "$BEHIND" = "0" ] && [ "$AHEAD" = "0" ]; then
  exit 0
fi

echo "[dotfiles] upstream check ($UP):"
if [ "$BEHIND" != "0" ]; then
  echo "  $BEHIND commit(s) behind — new on upstream:"
  git -C "$DOTFILES_ROOT" log --oneline HEAD..@{u} 2>/dev/null | sed 's/^/    /'
  echo "  changed files:"
  git -C "$DOTFILES_ROOT" diff --stat HEAD @{u} 2>/dev/null | sed 's/^/    /'
  SENSITIVE=$(git -C "$DOTFILES_ROOT" diff --name-only HEAD @{u} 2>/dev/null | grep -E '\.githooks/|secrets/|\.config/gpg/|\.ssh|id_|key|\.env' || true)
  if [ -n "$SENSITIVE" ]; then
    echo "  WARNING: sensitive paths changed upstream:"
    echo "$SENSITIVE" | sed 's/^/    /'
  fi
fi
if [ "$AHEAD" != "0" ]; then
  echo "  $AHEAD commit(s) ahead — divergence, reconcile before push:"
  git -C "$DOTFILES_ROOT" log --oneline @{u}..HEAD 2>/dev/null | sed 's/^/    /'
fi
echo "[dotfiles] review: git -C $DOTFILES_ROOT log HEAD..@{u}"
exit 0

#!/bin/sh
# dotfiles-check.sh — fail-silent upstream fetch + review.
# Runs at interactive shell init (throttled). Prints nothing when up to date.
# Safe: never blocks login; network calls are time-bounded and errors swallowed.

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$CACHE_DIR" 2> /dev/null

# Throttle: at most one network check per 30 minutes per machine.
THROTTLE=1800
STAMP="$CACHE_DIR/last-fetch-check"
NOW=$(date +%s)
LAST=0
[ -f "$STAMP" ] && LAST=$(tr -d '\n' < "$STAMP" 2> /dev/null | grep -E '^[0-9]+$' || echo 0)
if [ $((NOW - LAST)) -lt "$THROTTLE" ]; then
  exit 0
fi
echo "$NOW" > "$STAMP" 2> /dev/null

# Need an upstream to compare against.
UP=$(git -C "$DOTFILES_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null)
[ -z "$UP" ] && exit 0

# Fail-silent, time-bounded fetch of the resolved upstream (timeout kills a
# stalled/black-holed SSH session so login can never hang). `|| true` swallows
# failures (offline, auth, timeout).
timeout 10 git -C "$DOTFILES_ROOT" fetch "$UP" --quiet 2> /dev/null || true

# Two-dot ranges: HEAD..@{u} = ahead of us (we are behind); @{u}..HEAD = ahead of upstream.
BEHIND=$(git -C "$DOTFILES_ROOT" rev-list --count HEAD..'@{u}' 2> /dev/null || echo 0)
AHEAD=$(git -C "$DOTFILES_ROOT" rev-list --count '@{u}'..HEAD 2> /dev/null || echo 0)

if [ "$BEHIND" = "0" ] && [ "$AHEAD" = "0" ]; then
  exit 0
fi

echo "[dotfiles] upstream check ($UP):"
if [ "$BEHIND" != "0" ]; then
  echo "  $BEHIND commit(s) behind — new on upstream:"
  git -C "$DOTFILES_ROOT" log --oneline HEAD..'@{u}' 2> /dev/null | sed 's/^/    /'
  echo "  changed files:"
  git -C "$DOTFILES_ROOT" diff --stat HEAD '@{u}' 2> /dev/null | sed 's/^/    /'
  SENSITIVE=$(git -C "$DOTFILES_ROOT" diff --name-only HEAD '@{u}' 2> /dev/null | grep -E '\.sops\.yaml|\.githooks/|secrets|\.config/gpg/|\.ssh|id_(rsa|ed25519)|\.key$|pinentry|\.env' || true)
  if [ -n "$SENSITIVE" ]; then
    echo "  WARNING: sensitive paths changed upstream:"
    printf '%s\n' "$SENSITIVE" | while IFS= read -r _line; do
      printf '    %s\n' "$_line"
    done
  fi
fi
if [ "$AHEAD" != "0" ]; then
  echo "  $AHEAD commit(s) ahead — reconcile before push:"
  git -C "$DOTFILES_ROOT" log --oneline '@{u}'..HEAD 2> /dev/null | sed 's/^/    /'
fi
echo '[dotfiles] review: git -C '"$DOTFILES_ROOT"' log HEAD..@{u}'
exit 0

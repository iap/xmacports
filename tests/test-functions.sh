#!/bin/bash
# Function tests for dotfiles — run from your real shell: bash tests/test-functions.sh
# Tests must be run after `make bootstrap` so symlinks exist.
# shellcheck disable=SC2016  # intentional quote-splicing for bash -c strings
# shellcheck disable=SC2015  # intentional pass/fail pattern: A && pass || fail
# shellcheck disable=SC2086  # basename args in test descriptions are safe

DOTFILES="$HOME/.dotfiles"
PASSED=0
FAILED=0

pass() {
  echo "PASS: $1"
  PASSED=$((PASSED + 1))
}
fail() {
  echo "FAIL: $1"
  FAILED=$((FAILED + 1))
}

check() {
  local desc="$1"
  shift
  if "$@" 2> /dev/null; then pass "$desc"; else fail "$desc"; fi
}

echo "Dotfiles Function Tests"
date '+%Y-%m-%d %H:%M:%S'
echo

# ── 1. File structure ────────────────────────────────────────────────────────
echo "1. File structure"
for f in \
  "$DOTFILES/.zshrc" \
  "$DOTFILES/.zprofile" \
  "$DOTFILES/.bashrc" \
  "$DOTFILES/.profile" \
  "$DOTFILES/.config/env.d/default.sh" \
  "$DOTFILES/.zshrc.d/env.sh" \
  "$DOTFILES/.zshrc.d/functions.sh" \
  "$DOTFILES/.zshrc.d/aliases.sh" \
  "$DOTFILES/.zshrc.d/prompt.sh" \
  "$DOTFILES/scripts/timeout_prompt.sh"; do
  check "exists: $(basename $f)" test -f "$f"
done
echo

# ── 2. Syntax ────────────────────────────────────────────────────────────────
echo "2. Syntax"
for f in \
  "$DOTFILES/.zshrc" \
  "$DOTFILES/.zprofile" \
  "$DOTFILES/.zshrc.d/env.sh" \
  "$DOTFILES/.zshrc.d/functions.sh" \
  "$DOTFILES/.zshrc.d/aliases.sh" \
  "$DOTFILES/.zshrc.d/prompt.sh" \
  "$DOTFILES/.config/env.d/default.sh"; do
  check "zsh syntax: $(basename $f)" zsh -n "$f"
done
check "bash syntax: .bashrc" bash -n "$DOTFILES/.bashrc"
check "bash syntax: .profile" bash -n "$DOTFILES/.profile"
check "bash syntax: default.sh" bash -n "$DOTFILES/.config/env.d/default.sh"
echo

# ── 3. Symlinks ──────────────────────────────────────────────────────────────
echo "3. Symlinks (requires make bootstrap)"
for f in .zshrc .zprofile .bashrc .profile .gitconfig .vimrc; do
  check "symlink: ~/$f" test -L "$HOME/$f"
done
echo

# ── 4. Bash PS1 — escape codes not literal variable names ────────────────────
echo "4. Bash PS1 color fix"
ps1_test=$(bash -c '
  source '"$DOTFILES"'/.bashrc 2>/dev/null
  RED="\033[0;31m"; GREEN="\033[0;32m"; BLUE="\033[0;34m"
  CYAN="\033[0;36m"; RESET="\033[0m"
  PS1="\[${CYAN}\]\w\[${RESET}\]"
  PS1+="\[${BLUE}\]\$(git_prompt)\[${RESET}\]"
  PS1+=" \[${GREEN}\]❯\[${RESET}\] "
  echo "$PS1" | grep -c "\${CYAN}"
')
[[ "$ps1_test" -eq 0 ]] && pass "PS1 has no literal \${CYAN}" || fail "PS1 still has literal \${CYAN}"

ps1_codes=$(bash -c '
  RED="\033[0;31m"; GREEN="\033[0;32m"; BLUE="\033[0;34m"
  CYAN="\033[0;36m"; RESET="\033[0m"
  PS1="\[${CYAN}\]\w\[${RESET}\]"
  PS1+="\[${BLUE}\]\$(git_prompt)\[${RESET}\]"
  PS1+=" \[${GREEN}\]❯\[${RESET}\] "
  echo "$PS1" | cat -v | grep -c "033"
')
[[ "$ps1_codes" -gt 0 ]] && pass "PS1 contains ANSI escape codes" || fail "PS1 missing ANSI escape codes"
echo

# ── 5. GPG_TTY — single line, no "not a tty" corruption ─────────────────────
echo "5. GPG_TTY fix"
gpg_tty_lines=$(bash -c '
  source '"$DOTFILES"'/.config/env.d/default.sh 2>/dev/null
  printf "%s" "$GPG_TTY" | wc -l | tr -d " "
')
[[ "$gpg_tty_lines" -eq 0 ]] && pass "GPG_TTY is single line (no newline)" || fail "GPG_TTY has $gpg_tty_lines newlines"

gpg_tty_val=$(bash -c '
  source '"$DOTFILES"'/.config/env.d/default.sh 2>/dev/null
  echo "$GPG_TTY"
')
[[ "$gpg_tty_val" != *"not a tty"* ]] && pass "GPG_TTY has no 'not a tty'" || fail "GPG_TTY contains 'not a tty': [$gpg_tty_val]"
echo

# ── 6. HISTFILE/SAVEHIST not in default.sh ───────────────────────────────────
echo "6. HISTFILE/SAVEHIST placement"
check "HISTFILE not exported in default.sh" bash -c '
  ! grep -q "^export HISTFILE" '"$DOTFILES"'/.config/env.d/default.sh
'
check "SAVEHIST not exported in default.sh" bash -c '
  ! grep -q "^export SAVEHIST" '"$DOTFILES"'/.config/env.d/default.sh
'
check "HISTFILE set in .zshrc" bash -c '
  grep -q "HISTFILE" '"$DOTFILES"'/.zshrc
'
echo

# ── 7. ZSH functions ─────────────────────────────────────────────────────────
echo "7. ZSH functions"
check "mkcd creates dir and cds" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/functions.sh
  tmp=$(mktemp -d)
  mkcd "$tmp/testdir" && [[ "$(pwd)" == "$tmp/testdir" ]]
  rm -rf "$tmp"
'
check "log_info outputs message" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/functions.sh
  out=$(log_info "hello")
  [[ "$out" == *"hello"* ]]
'
check "showfile works on existing file" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/functions.sh
  out=$(showfile '"$DOTFILES"'/.zshrc)
  [[ "$out" == *"FILE:"* ]]
'
check "findfile returns results" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/functions.sh
  out=$(findfile zshrc)
  [[ -n "$out" ]]
'
check "gitstat works in git repo" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/functions.sh
  cd '"$DOTFILES"'
  out=$(gitstat)
  [[ "$out" == *"REPO:"* && "$out" == *"BRANCH:"* ]]
'
echo

# ── 8. ZSH prompt ────────────────────────────────────────────────────────────
echo "8. ZSH prompt"
check "short_pwd truncates long paths" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/prompt.sh
  out=$(PWD="/a/very/long/path/that/exceeds/thirty/characters" short_pwd)
  [[ ${#out} -le 31 ]]
'
check "build_prompt produces output" zsh -c '
  SHELL_CACHE_DIR=/tmp/dotfiles-test-$$
  source '"$DOTFILES"'/.zshrc.d/prompt.sh
  # exit code passed as arg
  out=$(build_prompt 0)
  rm -rf /tmp/dotfiles-test-$$
  [[ -n "$out" ]]
'
check "build_prompt shows exit code on failure" zsh -c '
  SHELL_CACHE_DIR=/tmp/dotfiles-test-$$
  source '"$DOTFILES"'/.zshrc.d/prompt.sh
  # exit code passed as arg
  out=$(build_prompt 127)
  rm -rf /tmp/dotfiles-test-$$
  [[ "$out" == *"127"* ]]
'
check "git_info returns branch in git repo" zsh -c '
  SHELL_CACHE_DIR=/tmp/dotfiles-test-$$
  source '"$DOTFILES"'/.zshrc.d/prompt.sh
  cd '"$DOTFILES"'
  out=$(git_info)
  rm -rf /tmp/dotfiles-test-$$
  [[ "$out" == *"main"* || "$out" == *"master"* || -n "$out" ]]
'
echo

# ── 9. Aliases ───────────────────────────────────────────────────────────────
echo "9. Aliases"
check "brew protection works" zsh -c '
  source '"$DOTFILES"'/.zshrc.d/aliases.sh
  out=$(brew 2>&1 || true)
  [[ "$out" == *"MacPorts"* ]]
'
check "ls alias set" zsh -c '
  source '"$DOTFILES"'/.config/env.d/default.sh
  alias ls | grep -q "color"
'
check "grep alias set" zsh -c '
  source '"$DOTFILES"'/.config/env.d/default.sh
  alias grep | grep -q "color"
'
echo

# ── 10. Timeout prompt ───────────────────────────────────────────────────────
echo "10. Timeout prompt"
check "timeout_prompt returns default on timeout" bash -c '
  source '"$DOTFILES"'/scripts/timeout_prompt.sh
  result=$(echo "" | timeout_prompt "test" 1 "mydefault" 2>/dev/null)
  [[ "$result" == "mydefault" ]]
'
check "timeout_confirm returns 1 on default n" bash -c '
  source '"$DOTFILES"'/scripts/timeout_prompt.sh
  echo "n" | timeout_confirm "test" 1 "n" 2>/dev/null && exit 1 || exit 0
'
echo

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$((PASSED + FAILED))
echo "────────────────────────────────"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "All tests passed!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

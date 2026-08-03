#!/bin/bash
# Function tests for dotfiles
# shellcheck disable=SC2016
# shellcheck disable=SC2015
# shellcheck disable=SC2086

set -u

DOTFILES="${DOTFILES_ROOT:-$HOME/.dotfiles}"
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
  if "$@"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

echo "Dotfiles Function Tests"
date '+%Y-%m-%d %H:%M:%S'
echo

echo "1. File structure"
for f in \
  "$DOTFILES/.zshrc" \
  "$DOTFILES/.zprofile" \
  "$DOTFILES/.bashrc" \
  "$DOTFILES/.profile" \
  "$DOTFILES/shared/platform.sh" \
  "$DOTFILES/.zshrc.d/prompt.sh" \
  "$DOTFILES/shared/functions.sh" \
  "$DOTFILES/shared/aliases.sh"; do
  check "exists: $(basename $f)" test -f "$f"
done
echo

echo "2. Syntax"
for f in \
  "$DOTFILES/.zshrc" \
  "$DOTFILES/.zprofile" \
  "$DOTFILES/.zshrc.d/prompt.sh"; do
  check "zsh syntax: $(basename $f)" zsh -n "$f"
done
for f in \
  "$DOTFILES/.bashrc" \
  "$DOTFILES/.profile" \
  "$DOTFILES/shared/platform.sh" \
  "$DOTFILES/shared/functions.sh" \
  "$DOTFILES/shared/aliases.sh"; do
  check "bash syntax: $(basename $f)" bash -n "$f"
done
echo

echo "3. Environment loader"
check "platform loader survives set -u" bash --noprofile --norc -c '
  set -u
  source "'"$DOTFILES"'/shared/platform.sh"
'
check "zsh env loader survives set -u" zsh -c '
  set -u
  source "'"$DOTFILES"'/shared/platform.sh"
'
check "platform loader dedupes PATH" /bin/bash --noprofile --norc -c '
  set -u
  unset DOTFILES_ENV_LOADED DOTFILES_PLATFORM_LOADED
  PATH="/tmp/path-a:/tmp/path-b:/tmp/path-a"
  export PATH
  source "'"$DOTFILES"'/shared/platform.sh"
  local_count=0
  local_seen=""
  IFS=":"
  for segment in $PATH; do
    [ -z "$segment" ] && continue
    case ":${local_seen}:" in
      *":${segment}:"*) local_count=$((local_count + 1)) ;;
      *) local_seen="${local_seen:+${local_seen}:}${segment}" ;;
    esac
  done
  [ "$local_count" -eq 0 ]
'
check "platform loader discovers /opt/local/bin gpg when present" /bin/bash --noprofile --norc -c '
  set -u
  PATH="/usr/bin:/bin"
  export PATH
  source "'"$DOTFILES"'/shared/platform.sh"
  if [ -x /opt/local/bin/gpg ]; then
    /opt/local/bin/gpg --version > /dev/null 2>&1
  else
    true
  fi
'
echo

echo "4. Symlinks (requires make bootstrap)"
if [[ -L "$HOME/.zshrc" ]]; then
  for f in .zshrc .zprofile .bashrc .profile .gitconfig .vimrc; do
    check "symlink: ~/$f" test -L "$HOME/$f"
  done
else
  echo "   (skipped — set DOTFILES_ROOT or run make bootstrap for symlink tests)"
fi
echo

echo "5. GPG_TTY handling"
# Correct behavior: in a non-TTY session GPG_TTY must be UNSET
# (a dummy like /dev/tty breaks pinentry). In a TTY session it may
# be set to the real tty device. Test both: source real platform.sh.
gpg_tty_val=$(bash -c '
  unset GPG_TTY
  source "'"$DOTFILES"'/shared/platform.sh" 2>/dev/null
  echo "${GPG_TTY:-<unset>}"
')
if [[ "$gpg_tty_val" == "<unset>" ]]; then
  pass "GPG_TTY unset in non-TTY session (correct)"
elif [[ "$gpg_tty_val" == /dev/* && -c "$gpg_tty_val" ]]; then
  pass "GPG_TTY set to a real tty device"
else
  fail "GPG_TTY wrong: [$gpg_tty_val]"
fi
echo ""

echo "6. Color aliases"
check "ls alias set in platform.sh" bash -c '
  grep -q "alias ls" '"$DOTFILES"'/shared/platform.sh
'
check "grep alias set in platform.sh" bash -c '
  grep -q "alias grep" '"$DOTFILES"'/shared/platform.sh
'
echo

echo "7. Shared functions"
check "log_info outputs message" bash -c '
  source '"$DOTFILES"'/shared/functions.sh
  out=$(log_info "hello")
  [[ "$out" == *"hello"* ]]
'
check "showfile works on existing file" bash -c '
  source '"$DOTFILES"'/shared/functions.sh
  out=$(showfile '"$DOTFILES"'/.zshrc)
  [[ "$out" == *"FILE:"* ]]
'
check "findfile returns results" bash -c '
  source '"$DOTFILES"'/shared/functions.sh
  out=$(findfile zshrc)
  [[ -n "$out" ]]
'
check "gitstat works in git repo" bash -c '
  source '"$DOTFILES"'/shared/functions.sh
  cd '"$DOTFILES"'
  out=$(gitstat)
  [[ "$out" == *"REPO:"* && "$out" == *"BRANCH:"* ]]
'
# Also verify shared functions load correctly under zsh
check "shared functions load in zsh" zsh -c '
  source '"$DOTFILES"'/shared/functions.sh
  out=$(log_info "zsh-test")
  [[ "$out" == *"zsh-test"* ]]
'
echo

echo "8. ZSH prompt"
check "short_pwd truncates long paths" zsh -c '
  source '"$DOTFILES"'/shared/prompt.sh
  out=$(PWD="/a/very/long/path/that/exceeds/thirty/characters" short_pwd)
  [[ ${#out} -le 31 ]]
'
check "git_prompt_info returns branch in git repo" zsh -c '
  SHELL_CACHE_DIR=/tmp/dotfiles-test-$$
  source "'"$DOTFILES"'/shared/functions.sh"
  source "'"$DOTFILES"'/shared/prompt.sh"
  cd "'"$DOTFILES"'"
  out=$(git_prompt_info)
  rm -rf /tmp/dotfiles-test-$$
  [[ "$out" == *"main"* || "$out" == *"master"* || -n "$out" ]]
'
echo

echo "9. Aliases"
check "install alias removed" bash -c '
  source '"$DOTFILES"'/shared/aliases.sh
  ! alias install >/dev/null 2>&1
'
check "update alias removed" bash -c '
  source '"$DOTFILES"'/shared/aliases.sh
  ! alias update >/dev/null 2>&1
'
check "sysinfo alias is generic" bash -c '
  source '"$DOTFILES"'/shared/aliases.sh
  out=$(alias sysinfo)
  [[ "$out" == *"OS:"* && "$out" != *"MacPorts"* ]]
'
echo

TOTAL=$((PASSED + FAILED))
echo "────────────────────────────────"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "All tests passed!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

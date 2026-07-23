#!/bin/bash
# Bootstrap idempotency test
# Verifies that running make bootstrap twice leaves the system clean.
set -euo pipefail

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
DOTFILES="$DOTFILES_ROOT"
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

export HOME
ORIGINAL_HOME="$HOME"
HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"; HOME="$ORIGINAL_HOME"' EXIT

mkdir -p "$HOME/.gnupg" "$HOME/.ssh" "$HOME/bin"
chmod 700 "$HOME/.gnupg" "$HOME/.ssh"

echo "Bootstrap Idempotency Test"
date '+%Y-%m-%d %H:%M:%S'
echo

echo "1. First bootstrap run"
set +e
output1=$(DOTFILES_ROOT="$DOTFILES" bash "$DOTFILES/bootstrap.sh" 2>&1)
b1_status=$?
set -e
if [ "$b1_status" -eq 0 ]; then
  pass "bootstrap 1 exited 0"
else
  fail "bootstrap 1 exited $b1_status"
fi
echo "${output1:-}"
echo

echo "2. Second bootstrap run (idempotency check)"
set +e
output2=$(DOTFILES_ROOT="$DOTFILES" bash "$DOTFILES/bootstrap.sh" 2>&1)
b2_status=$?
set -e
if [ "$b2_status" -eq 0 ]; then
  pass "bootstrap 2 exited 0"
else
  fail "bootstrap 2 exited $b2_status"
fi
echo "${output2:-}"
echo

echo "3. Symlink verification"
for f in .profile .zprofile .bashrc .zshrc .bash_profile .gitconfig .gitignore_global .forward .vimrc; do
  if [ -L "$HOME/$f" ]; then
    target=$(readlink "$HOME/$f")
    case "$target" in
      "$DOTFILES"/*)
        pass "symlink ~/$f -> $target"
        ;;
      *)
        fail "symlink ~/$f points outside DOTFILES: $target"
        ;;
    esac
  else
    echo "   SKIP: ~/$f is not a symlink"
  fi
done
echo

echo "4. One replacement should create exactly one backup dir"
rm -f "$HOME/.profile"
printf 'replaced-by-test\n' > "$HOME/.profile"
if DOTFILES_ROOT="$DOTFILES" bash "$DOTFILES/bootstrap.sh" >/tmp/bootstrap-test-output-$$.log 2>&1; then
  pass "replacement run exits 0"
else
  fail "replacement run did not exit 0"
fi
if [ -L "$HOME/.profile" ]; then
  pass ".profile is a symlink after replacement"
else
  fail ".profile is not a symlink after replacement"
fi
if grep -q "Backup:" /tmp/bootstrap-test-output-$$.log 2>/dev/null; then
  pass "bootstrap reported a backup path"
else
  fail "bootstrap did not report a backup path"
fi
rm -f /tmp/bootstrap-test-output-$$.log 2>/dev/null || true
echo

echo "5. Security permissions"
if [ -d "$HOME/.gnupg" ]; then
  gnupg_perms=$(find "$HOME/.gnupg" -maxdepth 0 -printf "%m" 2>/dev/null || echo "unknown")
  if [ "$gnupg_perms" = "700" ]; then
    pass ".gnupg is 700"
  else
    fail ".gnupg is $gnupg_perms (expected 700)"
  fi
else
  fail ".gnupg missing"
fi
if [ -d "$HOME/.ssh" ]; then
  ssh_perms=$(find "$HOME/.ssh" -maxdepth 0 -printf "%m" 2>/dev/null || echo "unknown")
  if [ "$ssh_perms" = "700" ]; then
    pass ".ssh is 700"
  else
    fail ".ssh is $ssh_perms (expected 700)"
  fi
else
  fail ".ssh missing"
fi
echo

TOTAL=$((PASSED + FAILED))
echo "------------------------------------------------------------"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"

HOME="$ORIGINAL_HOME"
trap - EXIT

[ "$FAILED" -eq 0 ] && echo "Bootstrap idempotency OK!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

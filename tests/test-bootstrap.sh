#!/bin/bash
# Bootstrap idempotency test
# Verifies that running make bootstrap twice leaves the system clean.
# shellcheck disable=SC2015

set -u

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

echo "Bootstrap Idempotency Test"
date '+%Y-%m-%d %H:%M:%S'
echo

# Save originals and ensure clean state
echo "Preparing test environment..."
for f in .profile .bashrc .zshrc .zprofile .vimrc .gitconfig .gitignore_global .forward; do
  if [ -L "$HOME/$f" ]; then
    rm -f "$HOME/$f"
  fi
  touch "$HOME/$f" 2> /dev/null || true
done
chmod 600 "$HOME/.forward" "$HOME/.vimrc" 2> /dev/null || true

# Run bootstrap once
echo "1. First bootstrap run"
output1=$(DOTFILES_ROOT="$DOTFILES" bash "$DOTFILES/bootstrap.sh" 2>&1)
b1_status=$?
if [ $b1_status -eq 0 ]; then
  pass "bootstrap 1 exited 0"
else
  fail "bootstrap 1 exited $b1_status"
fi
echo "$output1"
echo

# Run bootstrap twice
echo "2. Second bootstrap run (idempotency check)"
output2=$(DOTFILES_ROOT="$DOTFILES" bash "$DOTFILES/bootstrap.sh" 2>&1)
b2_status=$?
if [ $b2_status -eq 0 ]; then
  pass "bootstrap 2 exited 0"
else
  fail "bootstrap 2 exited $b2_status"
fi
echo "$output2"
echo

# Verify symlinks point to DOTFILES_ROOT
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

# Verify backup created on first run, no duplicate on second
echo "4. Backup count"
backups=$(find "$HOME" -maxdepth 1 -type d -name ".dotfiles-backup-*" 2> /dev/null | wc -l | tr -d ' ')
if [ "$backups" -eq 1 ]; then
  pass "backup dirs: $backups (expected 1)"
else
  fail "backup dirs: $backups (expected 1, got $backups)"
fi
echo

# Verify GPG/SSH permissions
echo "5. Security permissions"
if [ -d "$HOME/.gnupg" ]; then
  perms=$(stat -f %Lp "$HOME/.gnupg" 2> /dev/null || stat -c %a "$HOME/.gnupg" 2> /dev/null || echo '?')
  if [ "$perms" = "700" ]; then
    pass ".gnupg is 700"
  else
    fail ".gnupg is $perms (expected 700)"
  fi
else
  fail ".gnupg missing"
fi
if [ -d "$HOME/.ssh" ]; then
  perms=$(stat -f %Lp "$HOME/.ssh" 2> /dev/null || stat -c %a "$HOME/.ssh" 2> /dev/null || echo '?')
  if [ "$perms" = "700" ]; then
    pass ".ssh is 700"
  else
    fail ".ssh is $perms (expected 700)"
  fi
else
  fail ".ssh missing"
fi
echo

TOTAL=$((PASSED + FAILED))
echo "────────────────────────────────"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"

# Cleanup: remove test symlinks and backup dirs
echo "Cleaning up test artifacts..."
for f in .profile .zprofile .bashrc .zshrc .bash_profile .gitconfig .gitignore_global .forward .vimrc; do
  if [ -L "$HOME/$f" ]; then
    rm -f "$HOME/$f"
  fi
done
find "$HOME" -maxdepth 1 -type d -name ".dotfiles-backup-*" -exec rm -rf {} + 2> /dev/null || true

[[ $FAILED -eq 0 ]] && echo "✅ Bootstrap idempotency OK!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

#!/bin/bash
# Compliance checker

set -eu

LOG_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}/.cache/logs"
COMPLIANCE_LOG="$LOG_ROOT/compliance-$(date +%Y-%m-%d).log"
mkdir -p "$LOG_ROOT"

log_check() {
  local status="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $status: $message" | tee -a "$COMPLIANCE_LOG"
}

echo "System Rules Compliance Check"

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

for profile in .profile .bashrc .zshrc .zprofile; do
  if [[ -f "$DOTFILES_ROOT/$profile" ]]; then
    log_check "PASS" "Required profile $profile exists"
  else
    log_check "FAIL" "Missing required profile $profile"
  fi
done

if grep -r --include="*.sh" --include="*.zsh" --exclude="compliance-check.sh" --exclude-dir=.git --exclude-dir=examples \
  -E 'sudo (port|apt-get|dnf|pacman)|command -v (port|brew)|sudo port|brew install|apt-get install|dnf install|pacman -S' \
  "$DOTFILES_ROOT/" > /dev/null 2>&1; then
  log_check "WARN" "Package-manager commands still exist in tracked scripts"
  grep -r --include="*.sh" --include="*.zsh" --exclude="compliance-check.sh" --exclude-dir=.git --exclude-dir=examples \
    -E 'sudo (port|apt-get|dnf|pacman)|command -v (port|brew)|sudo port|brew install|apt-get install|dnf install|pacman -S' \
    "$DOTFILES_ROOT/" | head -5
else
  log_check "PASS" "No package-manager automation detected in tracked scripts"
fi

for dir in .config .local/share .cache .local/state; do
  if [[ -d "$HOME/$dir" ]]; then
    log_check "PASS" "XDG directory $dir exists"
  else
    log_check "FAIL" "Missing XDG directory $dir"
  fi
done

if grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples \
  -E "^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+" \
  "$DOTFILES_ROOT/" | grep -v "sed 's|" > /dev/null 2>&1; then
  log_check "WARN" "Hardcoded paths found in scripts - should use dynamic resolution"
  grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples \
    -E "^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+" \
    "$DOTFILES_ROOT/" | grep -v "sed 's|" 2> /dev/null | head -5
else
  log_check "PASS" "No hardcoded paths detected in scripts"
fi

echo "Compliance check complete. Log: $COMPLIANCE_LOG"

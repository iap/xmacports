#!/bin/bash
# Compliance checker

set -eu

LOG_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/logs"
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
  -E '^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+' \
  "$DOTFILES_ROOT/" | grep -v "sed 's|" > /dev/null 2>&1; then
  log_check "WARN" "Hardcoded paths found in scripts - should use dynamic resolution"
  grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples \
    -E '^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+' \
    "$DOTFILES_ROOT/" | grep -v "sed 's|" 2> /dev/null | head -5
else
  log_check "PASS" "No hardcoded paths detected in scripts"
fi

echo ""
echo "4. Secrets Migration (Keybase -> SOPS + age)"

if grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples --exclude-dir=tests --exclude="compliance-check.sh" \
  -E 'keybase|kvstore|kbfs' \
  "$DOTFILES_ROOT/" > /dev/null 2>&1; then
  log_check "FAIL" "Keybase references found in production code"
  grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples --exclude-dir=tests --exclude="compliance-check.sh" \
    -E 'keybase|kvstore|kbfs' \
    "$DOTFILES_ROOT/" | head -5
else
  log_check "PASS" "No Keybase references in production code"
fi

if [[ -f "$DOTFILES_ROOT/.sops.yaml" ]]; then
  log_check "PASS" ".sops.yaml configuration present"
  if grep -qE 'age: +age1' "$DOTFILES_ROOT/.sops.yaml"; then
    log_check "PASS" "age public key configured"
  else
    log_check "WARN" ".sops.yaml age key looks like placeholder"
  fi
else
  log_check "FAIL" ".sops.yaml configuration missing"
fi

if [[ -f "$DOTFILES_ROOT/secrets/secrets.enc.yaml" ]]; then
  log_check "PASS" "secrets.enc.yaml present"
else
  log_check "WARN" "secrets.enc.yaml missing (run make secrets-init)"
fi

echo "Compliance check complete. Log: $COMPLIANCE_LOG"

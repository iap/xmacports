#!/bin/bash
# System rules compliance checker
# Validates dotfiles against development environment requirements

set -e

COMPLIANCE_LOG="$HOME/.cache/logs/compliance-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$COMPLIANCE_LOG")"

log_check() {
  local status="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $status: $message" | tee -a "$COMPLIANCE_LOG"
}

echo "System Rules Compliance Check"

# Check required shell profiles
for profile in .profile .bashrc .zshrc .zprofile; do
  if [[ -f "$HOME/.dotfiles/$profile" ]]; then
    log_check "PASS" "Required profile $profile exists"
  else
    log_check "FAIL" "Missing required profile $profile"
  fi
done

# Check MacPorts prefix (dynamic detection)
MACPORTS_PREFIX="$(command -v port 2> /dev/null | sed 's|/bin/port||' || echo '/opt/local')"
if [[ "$PATH" =~ $MACPORTS_PREFIX ]]; then
  log_check "PASS" "MacPorts prefix ($MACPORTS_PREFIX) in PATH"
else
  log_check "FAIL" "MacPorts prefix ($MACPORTS_PREFIX) not found in PATH"
fi

# Check for Homebrew (should not exist)
if command -v brew > /dev/null 2>&1; then
  log_check "WARN" "Homebrew found - should be disabled per system rules"
else
  log_check "PASS" "Homebrew not found (compliant)"
fi

# Check XDG compliance
for dir in .config .local/share .cache .local/state; do
  if [[ -d "$HOME/$dir" ]]; then
    log_check "PASS" "XDG directory $dir exists"
  else
    log_check "FAIL" "Missing XDG directory $dir"
  fi
done

# Check dynamic path resolution in scripts
# Only check shell scripts, exclude documentation and examples
# Look for actual hardcoded paths, not variables or fallback patterns
if grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples \
  -E "^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+" \
  "$HOME/.dotfiles/" | grep -v "echo '/opt/local'" | grep -v "sed 's|" > /dev/null 2>&1; then
  log_check "WARN" "Hardcoded paths found in scripts - should use dynamic resolution"
  grep -r --include="*.sh" --include="*.zsh" --exclude-dir=.git --exclude-dir=examples \
    -E "^[^#=]*=[^$]*/(Users|home)/[a-zA-Z0-9_-]+[^)]|^[^#]*/(Users|home)/[a-zA-Z0-9_-]+" \
    "$HOME/.dotfiles/" | grep -v "echo '/opt/local'" | grep -v "sed 's|" 2> /dev/null | head -5
else
  log_check "PASS" "No hardcoded paths detected in scripts"
fi

echo "Compliance check complete. Log: $COMPLIANCE_LOG"

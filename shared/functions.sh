#!/bin/bash
# Shared functions — bash 4+ and zsh compatible, no shell-specific syntax

# Basic utility
mkcd() {
  mkdir -p "$1" && cd "$1" || return
}

# Simple logging
log_info() {
  echo "[$(date '+%H:%M:%S')] $1"
}

log_warn() {
  echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2
}

# GPG verification
verify_gpg_ssh() {
  if ! command -v gpg > /dev/null 2>&1; then
    log_warn "GPG not found, SSH authentication may not work"
    return 1
  fi
  if [ ! -S "$SSH_AUTH_SOCK" ]; then
    log_warn "GPG agent SSH socket not available"
    return 1
  fi
  log_info "GPG-SSH integration verified"
}

# System monitoring (macOS only)
temp_check() {
  if command -v powermetrics > /dev/null 2>&1; then
    sudo powermetrics --samplers smc_temp -n 1 2> /dev/null | grep -i temp || echo "Temperature monitoring unavailable"
  else
    echo "powermetrics not available"
  fi
}

battery_status() {
  pmset -g batt | grep -v "No estimate"
}

# Core context information
context() {
  echo "DIR: $(pwd)"
  echo "FILES: $(find . -maxdepth 1 -type f | wc -l | tr -d ' ')"
  if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d ' ') changes)"
  fi
}

# Simple file display
showfile() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "Usage: showfile <filename>"
    return 1
  fi
  local size
  size=$(stat -c %s "$file" 2> /dev/null || stat -f %z "$file" 2> /dev/null || echo '?')
  echo "FILE: $file ($size bytes)"
  cat "$file"
}

# Find files
findfile() {
  find . -name "*$1*" -type f 2> /dev/null | head -10
}

# Git status with structured output
gitstat() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not a git repository"
    return 1
  fi
  local root changes
  root="$(git rev-parse --show-toplevel)"
  changes="$(git status --porcelain)"
  echo "REPO: $(basename "$root")"
  echo "BRANCH: $(git branch --show-current)"
  echo "CHANGES: $(echo "$changes" | grep -c . 2> /dev/null || echo 0)"
  [ -n "$changes" ] && echo "$changes" | head -5
}

# System environment info
envinfo() {
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "OS: $(sw_vers -productVersion)"
    echo "MACPORTS: $(port version 2> /dev/null | head -1 || echo 'not bootstrapped')"
  else
    echo "OS: $(uname -sr)"
  fi
  echo "SHELL: $SHELL"
  echo "GIT: $(git --version 2> /dev/null | cut -d' ' -f3 || echo 'not bootstrapped')"
}

# GPG unlock helper
unlock_gpg() {
  echo "Unlocking GPG key..."
  echo "test" | gpg --clearsign > /dev/null 2>&1 && echo "✅ GPG key unlocked" || echo "❌ Failed to unlock"
}

# ─────────────────────────────────────────────────────────────────────────────
# Secret management — fetch secrets on demand, never export at shell startup
# Secrets are never stored in environment variables persistently.
# ─────────────────────────────────────────────────────────────────────────────

# Fetch a secret by key from Keybase kvstore (value encrypted, key name visible)
# Usage: secret <key> [namespace]
_secret_kvstore() {
  local key="$1" ns="${2:-dotfiles}"
  if ! command -v keybase > /dev/null 2>&1; then
    log_warn "keybase not found"
    return 1
  fi
  keybase kvstore api -m \
    "{\"method\":\"get\",\"params\":{\"options\":{\"namespace\":\"${ns}\",\"entryKey\":\"${key}\"}}}" \
    2> /dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); v=d.get('result',{}).get('entryValue',''); print(v) if v else exit(1)" \
    2> /dev/null
}

# Fetch a secret from Keybase encrypted filesystem
# Usage: _secret_kbfs <key>
_secret_kbfs() {
  local key="$1"
  local path="/keybase/private/${KEYBASE_USERNAME:-$(keybase whoami 2> /dev/null)}/secrets/${key}"
  keybase fs read "$path" 2> /dev/null
}

# Primary secret accessor — tries kvstore first, then KBFS
# Usage: secret <key> [namespace]
secret() {
  if [ -z "$1" ]; then
    echo "Usage: secret <key> [namespace]" >&2
    return 1
  fi
  _secret_kvstore "$1" "${2:-dotfiles}" || _secret_kbfs "$1" || {
    log_warn "secret '$1' not found in kvstore or KBFS"
    return 1
  }
}

# Run a command with a secret scoped as an env var for that process only.
# The secret is never exported to the shell environment.
# Usage: with_secret ENV_VAR_NAME=<key> [namespace] -- <command> [args...]
# Example: with_secret GITHUB_TOKEN=github-token -- gh repo list
with_secret() {
  local assignment="$1"
  shift
  local env_var key ns="dotfiles"
  env_var="${assignment%%=*}"
  key="${assignment#*=}"

  # Optional namespace before --
  if [ "$1" != "--" ] && [ -n "$1" ]; then
    ns="$1"
    shift
  fi
  [ "$1" = "--" ] && shift

  if [ -z "$env_var" ] || [ -z "$key" ] || [ -z "$1" ]; then
    echo "Usage: with_secret ENV_VAR=key [namespace] -- command [args...]" >&2
    return 1
  fi

  local value
  value=$(secret "$key" "$ns") || return 1
  env "${env_var}=${value}" "$@"
}

# Store a secret in Keybase kvstore
# Usage: secret_set <key> <value> [namespace]
secret_set() {
  local key="$1" value="$2" ns="${3:-dotfiles}"
  if [ -z "$key" ] || [ -z "$value" ]; then
    echo "Usage: secret_set <key> <value> [namespace]" >&2
    return 1
  fi
  if ! command -v keybase > /dev/null 2>&1; then
    log_warn "keybase not found"
    return 1
  fi
  local result
  result=$(keybase kvstore api -m \
    "{\"method\":\"put\",\"params\":{\"options\":{\"namespace\":\"${ns}\",\"entryKey\":\"${key}\",\"entryValue\":\"${value}\"}}}" \
    2> /dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print('ok') if 'result' in d else exit(1)" \
    2> /dev/null)
  if [ "$result" = "ok" ]; then
    echo "✅ secret '${key}' stored"
  else
    log_warn "failed to store secret '${key}'"
    return 1
  fi
}

# List all secret keys in a namespace
# Usage: secret_list [namespace]
secret_list() {
  local ns="${1:-dotfiles}"
  if ! command -v keybase > /dev/null 2>&1; then
    log_warn "keybase not found"
    return 1
  fi
  keybase kvstore api -m \
    "{\"method\":\"list\",\"params\":{\"options\":{\"namespace\":\"${ns}\"}}}" \
    2> /dev/null | python3 -c \
    "import sys,json; [print(e['entryKey']) for e in json.load(sys.stdin).get('result',{}).get('entryKeys',[])]" \
    2> /dev/null
}

# Delete a secret from Keybase kvstore
# Usage: secret_del <key> [namespace]
secret_del() {
  local key="$1" ns="${2:-dotfiles}"
  if [ -z "$key" ]; then
    echo "Usage: secret_del <key> [namespace]" >&2
    return 1
  fi
  local result
  result=$(keybase kvstore api -m \
    "{\"method\":\"del\",\"params\":{\"options\":{\"namespace\":\"${ns}\",\"entryKey\":\"${key}\"}}}" \
    2> /dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print('ok') if 'result' in d else exit(1)" \
    2> /dev/null)
  if [ "$result" = "ok" ]; then
    echo "✅ secret '${key}' deleted"
  else
    log_warn "failed to delete secret '${key}'"
    return 1
  fi
}

# Privacy and security functions
randomize_mac() {
  local interface="${1:-en0}"
  if [ "$(id -u)" -eq 0 ]; then
    local new_mac
    new_mac=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
    ifconfig "$interface" ether "$new_mac"
    echo "MAC randomized: $new_mac"
  else
    echo "Requires sudo: sudo randomize_mac"
  fi
}

check_privacy() {
  echo "WiFi MAC: $(ifconfig en0 2> /dev/null | grep ether | awk '{print $2}' || echo 'N/A')"
  echo "Private Address: $(system_profiler SPAirPortDataType 2> /dev/null | grep -q 'Private' && echo 'Enabled' || echo 'Check System Settings')"
  echo "Telemetry Blocking: $(env | grep -c 'TELEMETRY\|DO_NOT_TRACK\|ANALYTICS' || echo '0') variables set"
  echo "Network Connections (current user): $(lsof -i | wc -l | tr -d ' ') active"
}

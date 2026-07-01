#!/bin/bash
# Shared functions

set -u

mkcd() {
  [ $# -ge 1 ] || {
    echo "Usage: mkcd <dir>" >&2
    return 1
  }
  mkdir -p "$1" && cd "$1" || return
}

log_info() {
  echo "[$(date '+%H:%M:%S')] $1"
}

log_warn() {
  echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2
}

verify_gpg_ssh() {
  if ! command -v gpg > /dev/null 2>&1; then
    log_warn "GPG not found, SSH authentication may not work"
    return 1
  fi
  if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
    log_warn "GPG agent SSH socket not available"
    return 1
  fi
  log_info "GPG-SSH integration verified"
}

temp_check() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "temp_check is macOS only"
    return 1
  fi
  if command -v powermetrics > /dev/null 2>&1; then
    sudo powermetrics --samplers smc_temp -n 1 2> /dev/null | grep -i temp || echo "Temperature monitoring unavailable"
  else
    echo "powermetrics not available"
  fi
}

battery_status() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "battery_status is macOS only"
    return 1
  fi
  if command -v pmset > /dev/null 2>&1; then
    pmset -g batt | grep -v "No estimate"
  else
    echo "pmset not available"
  fi
}

context() {
  echo "DIR: $(pwd)"
  echo "FILES: $(find . -maxdepth 1 -type f | wc -l | tr -d ' ')"
  if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d ' ') changes)"
  fi
}

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

findfile() {
  find . -name "*${1}*" -type f 2> /dev/null | head -10
}

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

unlock_gpg() {
  echo "Unlocking GPG key..."
  echo "test" | gpg --clearsign > /dev/null 2>&1 && echo "✅ GPG key unlocked" || echo "❌ Failed to unlock"
}

# Secret management — SOPS + age backend
# Secrets are encrypted with age and stored in secrets/secrets.enc.yaml.
# The decrypted working copy lives in secrets/secrets.yaml (gitignored).
# Never export secrets at shell startup; fetch on demand only.
# Private age key: ~/.config/sops/age/keys.txt (never commit)

_SECRETS_ENC_FILE="${DOTFILES_ROOT:-$HOME/.dotfiles}/secrets/secrets.enc.yaml"
_SECRETS_PLAIN_FILE="${DOTFILES_ROOT:-$HOME/.dotfiles}/secrets/secrets.yaml"

_sops_available() {
  command -v sops > /dev/null 2>&1
}

_age_available() {
  command -v age > /dev/null 2>&1
}

_sops_decrypt() {
  if ! _sops_available; then
    log_warn "sops not found; install sops to use secret management"
    return 1
  fi
  if [ ! -f "$_SECRETS_ENC_FILE" ]; then
    log_warn "encrypted secrets file not found: $_SECRETS_ENC_FILE"
    return 1
  fi
  sops -d "$_SECRETS_ENC_FILE" 2> /dev/null
}

_sops_encrypt() {
  if ! _sops_available; then
    log_warn "sops not found; install sops to use secret management"
    return 1
  fi
  if [ ! -f "$_SECRETS_PLAIN_FILE" ]; then
    log_warn "plaintext secrets file not found: $_SECRETS_PLAIN_FILE"
    return 1
  fi
  sops -e "$_SECRETS_PLAIN_FILE" -o "$_SECRETS_ENC_FILE" 2> /dev/null
}

# Fetch a secret by key from the encrypted SOPS store.
# Usage: secret <key> [namespace]
secret() {
  if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: secret <key> [namespace]" >&2
    return 1
  fi
  local key="${1:-}" ns="${2:-dotfiles}"
  local decrypted
  decrypted=$(_sops_decrypt) || return 1
  if [ -z "$decrypted" ]; then
    log_warn "secret '$ns.$key' returned empty value"
    return 1
  fi
  echo "$decrypted" | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
n = d.get('${ns}', {})
v = n.get('${key}')
if v is None:
    sys.exit(1)
print(v, end='')
" 2> /dev/null || {
    log_warn "secret '$ns.$key' not found"
    return 1
  }
}

# Run a command with a secret scoped as an env var for that process only.
# The secret is never exported to the shell environment.
# Usage: with_secret ENV_VAR_NAME=<key> [namespace] -- <command> [args...]
# Example: with_secret GITHUB_TOKEN=github_token -- gh repo list
with_secret() {
  if [ $# -lt 2 ]; then
    echo "Usage: with_secret ENV_VAR=key [namespace] -- command [args...]" >&2
    return 1
  fi
  local assignment="$1"
  shift
  local env_var key ns="dotfiles"
  env_var="${assignment%%=*}"
  key="${assignment#*=}"

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

# List all top-level namespaces and keys in the encrypted store.
# Usage: secret_list [namespace]
secret_list() {
  local ns="${1:-}"
  local decrypted
  decrypted=$(_sops_decrypt) || return 1
  echo "$decrypted" | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
if '${ns}':
    n = d.get('${ns}', {})
    for k in n: print(k)
else:
    for ns, vals in d.items():
        print(f'[{ns}]')
        for k in vals: print(f'  {k}')
" 2> /dev/null
}

# Edit the decrypted secrets file in the configured editor.
# Usage: secrets_edit
secrets_edit() {
  local editor="${EDITOR:-vi}"
  if ! _sops_available; then
    log_warn "sops not found; install sops first"
    return 1
  fi
  if [ ! -f "$_SECRETS_ENC_FILE" ]; then
    log_warn "encrypted secrets file not found; run 'make secrets-init' first"
    return 1
  fi
  sops "$_SECRETS_ENC_FILE"
}

# Decrypt secrets to the working copy file.
# Usage: secrets_decrypt
secrets_decrypt() {
  if ! _sops_available; then
    log_warn "sops not found; install sops first"
    return 1
  fi
  _sops_decrypt > "$_SECRETS_PLAIN_FILE"
  chmod 600 "$_SECRETS_PLAIN_FILE"
  log_info "decrypted secrets -> $_SECRETS_PLAIN_FILE"
}

# Encrypt the working copy back to the committed encrypted file.
# Usage: secrets_encrypt
secrets_encrypt() {
  if ! _sops_available; then
    log_warn "sops not found; install sops first"
    return 1
  fi
  if [ ! -f "$_SECRETS_PLAIN_FILE" ]; then
    log_warn "plaintext secrets file not found: $_SECRETS_PLAIN_FILE"
    return 1
  fi
  _sops_encrypt
  log_info "encrypted secrets -> $_SECRETS_ENC_FILE"
}

randomize_mac() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "randomize_mac is macOS only"
    return 1
  fi
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
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "WiFi MAC: $(ifconfig en0 2> /dev/null | grep ether | awk '{print $2}' || echo 'N/A')"
    echo "Private Address: $(system_profiler SPAirPortDataType 2> /dev/null | grep -q 'Private' && echo 'Enabled' || echo 'Check System Settings')"
  else
    echo "WiFi MAC: $(ip link show 2> /dev/null | awk '/ether/{print $2}' | head -1 || echo 'N/A')"
  fi
  echo "Telemetry Blocking: $(env | grep -c 'TELEMETRY\|DO_NOT_TRACK\|ANALYTICS' || echo '0') variables set"
  echo "Network Connections (current user): $(lsof -i 2> /dev/null | wc -l | tr -d ' ') active"
}

#!/bin/bash
# Secret management — SOPS + age backend.
# Secrets are encrypted with age and stored in secrets/secrets.enc.yaml.
# The decrypted working copy lives in secrets/secrets.yaml (gitignored).
# Never export secrets at shell startup; fetch on demand only.
# Private age key: ~/.config/sops/age/keys.txt (never commit)

set -u

if [[ -n "${DOTFILES_SECRETS_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_SECRETS_LOADED=1

# Load platform detection for DOTFILES_ROOT
if [[ -f "$HOME/.dotfiles/shared/platform.sh" ]]; then
  source "$HOME/.dotfiles/shared/platform.sh"
fi

SECRET_PARSE_PY="${DOTFILES_ROOT:-$HOME/.dotfiles}/scripts/secret-parse.py"

_SECRETS_ENC_FILE="${DOTFILES_ROOT:-$HOME/.dotfiles}/secrets/secrets.enc.yaml"
_SECRETS_PLAIN_FILE="${DOTFILES_ROOT:-$HOME/.dotfiles}/secrets/secrets.yaml"
_SECRETS_CACHE=""

_sops_available() {
  command -v sops > /dev/null 2>&1
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
    log_warn "sops not found; install sops first"
    return 1
  fi
  if [ ! -f "$_SECRETS_PLAIN_FILE" ]; then
    log_warn "plaintext secrets file not found: $_SECRETS_PLAIN_FILE"
    return 1
  fi
  local lockdir="/tmp/.dotfiles-secrets-encrypt-$$"
  trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
  while ! mkdir "$lockdir" 2> /dev/null; do
    sleep 0.1
  done
  sops -e "$_SECRETS_PLAIN_FILE" -o "$_SECRETS_ENC_FILE" 2> /dev/null
  rmdir "$lockdir" 2> /dev/null || true
  trap - EXIT
}

_secrets_cache_get() {
  if [ -z "${_SECRETS_CACHE:-}" ]; then
    _SECRETS_CACHE=$(_sops_decrypt) || return 1
  fi
  printf '%s' "$_SECRETS_CACHE"
}

_secrets_cache_reset() {
  _SECRETS_CACHE=""
}

_validate_secret_name() {
  local name="$1"
  case "$name" in
    *[!a-zA-Z0-9_-]*)
      log_warn "invalid secret name: $name (only [a-zA-Z0-9_-] allowed)"
      return 1
      ;;
  esac
  return 0
}

_secret_yaml() {
  local decrypted
  decrypted=$(_secrets_cache_get) || return 1
  [ -z "$decrypted" ] && {
    log_warn "secret store returned empty value"
    return 1
  }
  command -v python3 > /dev/null 2>&1 || {
    log_warn "python3 not found; cannot parse secrets"
    return 1
  }
  [ -f "$SECRET_PARSE_PY" ] || {
    log_warn "secret-parse.py not found at $SECRET_PARSE_PY"
    return 1
  }
  printf '%s' "$decrypted"
}

# Fetch a secret by key from the encrypted SOPS store.
# Usage: secret <key> [namespace]
secret() {
  if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: secret <key> [namespace]" >&2
    return 1
  fi
  local key="${1:-}" ns="${2:-dotfiles}"
  _validate_secret_name "$key" || return 1
  _validate_secret_name "$ns" || return 1

  _secret_yaml | python3 "$SECRET_PARSE_PY" get "$ns" "$key" 2> /dev/null || {
    log_warn "secret $ns.$key not found"
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
  _secret_yaml | python3 "$SECRET_PARSE_PY" list "$ns" 2> /dev/null
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
  _secrets_cache_reset
  log_info "encrypted secrets -> $_SECRETS_ENC_FILE"
}

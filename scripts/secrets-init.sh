#!/bin/bash
# SOPS + age secret initialisation
# Generates an age keypair, configures .sops.yaml, and bootstraps the encrypted store.
# shellcheck disable=SC2015

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
SOPS_YAML="$DOTFILES_ROOT/.sops.yaml"
SECRETS_ENC="$DOTFILES_ROOT/secrets/secrets.enc.yaml"
SECRETS_EXAMPLE="$DOTFILES_ROOT/secrets/secrets.secrets.yaml.example"
SECRETS_PLAIN="$DOTFILES_ROOT/secrets/secrets.yaml"
SOPS_AGE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age"
SOPS_AGE_KEY="$SOPS_AGE_DIR/keys.txt"

require() {
  if ! command -v "$1" > /dev/null 2>&1; then
    echo "❌ Required tool not found: $1" >&2
    echo "   Install it manually, then re-run this script." >&2
    return 1
  fi
}

echo "SOPS + age secrets initialisation"
echo

require age
require sops
require python3

mkdir -p "$SOPS_AGE_DIR"
chmod 700 "$SOPS_AGE_DIR"

if [ -f "$SOPS_AGE_KEY" ]; then
  echo "⚠️  Age key already exists: $SOPS_AGE_KEY"
  echo "   Remove it first if you want to generate a new keypair."
else
  echo "Generating age keypair..."
  if command -v age-keygen > /dev/null 2>&1; then
    age-keygen -o "$SOPS_AGE_KEY"
  else
    echo "❌ age-keygen not found in PATH" >&2
    exit 1
  fi
  chmod 600 "$SOPS_AGE_KEY"
  AGENT_KEYS=$(age-keygen -y "$SOPS_AGE_KEY" 2> /dev/null || echo "")
  if [ -z "$AGENT_KEYS" ]; then
    echo "❌ Failed to extract public key from generated keypair" >&2
    exit 1
  fi
  PUBLIC_KEY="$(echo "$AGENT_KEYS" | grep -E '^age1' | head -1)"
  echo "   Public key: $PUBLIC_KEY"
  echo

  if [ -f "$SOPS_YAML" ]; then
    # The `age:` key is indented (4 spaces in practice), so anchor the match to
    # the actual leading whitespace and preserve it. The previous column-0
    # pattern silently no-op'd on indented files and would have broken the YAML
    # even if it had matched.
    if ! grep -q "age: $PUBLIC_KEY" "$SOPS_YAML"; then
      # Refuse to silently rewrite a .sops.yaml that already lists more than one
      # recipient. The unanchored sed below would drop every OTHER recipient and
      # leave the ciphertext unre-encryptable for other machines. If multiple
      # recipients are expected, add them explicitly with `sops updatekeys`.
      _recipient_count=$(grep -cE '^[[:space:]]*age: age1' "$SOPS_YAML" 2> /dev/null || echo 0)
      if [ "${_recipient_count:-0}" -gt 1 ]; then
        echo "❌ $SOPS_YAML lists $_recipient_count age recipients; refusing to" >&2
        echo "   overwrite them. Add the new key with: sops updatekeys $SECRETS_ENC" >&2
        exit 1
      fi
      echo "Updating .sops.yaml with generated public key..."
      sed -E "s/([[:space:]]*)age: age1[^[:space:]]*/\1age: $PUBLIC_KEY/" "$SOPS_YAML" > "$SOPS_YAML.tmp"
      mv "$SOPS_YAML.tmp" "$SOPS_YAML"
    fi
    if ! grep -q "age: $PUBLIC_KEY" "$SOPS_YAML"; then
      echo "❌ Failed to update public key in $SOPS_YAML" >&2
      exit 1
    fi
  else
    echo "Creating .sops.yaml..."
    cat > "$SOPS_YAML" << EOF
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    age: $PUBLIC_KEY
EOF
  fi
  echo "   -> $SOPS_YAML"
fi

echo

if [ -f "$SECRETS_ENC" ] && [ -s "$SECRETS_ENC" ]; then
  echo "⚠️  Encrypted secrets file already exists: $SECRETS_ENC"
  echo "   Use 'make secrets-encrypt' to re-encrypt after editing $SECRETS_PLAIN"
else
  # Tighten the umask up front so any plaintext we create (from the example or
  # an existing file) is 0600 from the moment it exists, not 0644 under the
  # caller's default umask. The chmod below is a belt-and-suspenders fallback.
  umask 077
  if [ -f "$SECRETS_EXAMPLE" ] && [ ! -f "$SECRETS_PLAIN" ]; then
    echo "Creating initial secrets.yaml from example..."
    cp "$SECRETS_EXAMPLE" "$SECRETS_PLAIN"
    chmod 600 "$SECRETS_PLAIN"
  fi
  if [ -f "$SECRETS_PLAIN" ]; then
    echo "Encrypting initial secrets..."
    sops -e "$SECRETS_PLAIN" -o "$SECRETS_ENC"
    chmod 600 "$SECRETS_PLAIN"
    echo "   -> $SECRETS_ENC"
    echo
    echo "✅ Encrypted secrets committed to git. Decrypted copy at:"
    echo "   $SECRETS_PLAIN (gitignored, mode 600)"
  else
    echo "No plaintext secrets found. Create secrets/secrets.yaml and run:"
    echo "   make secrets-encrypt"
  fi
fi

echo
echo "Next steps:"
echo "  1. Backup your private key: cp $SOPS_AGE_KEY ~/safe-backup/"
echo "  2. Edit secrets:      make secrets-edit   OR   sops secrets/secrets.enc.yaml"
echo "  3. Re-encrypt:       make secrets-encrypt"
echo "  4. Read a secret:    secret github_token dotfiles"
echo "  5. Use with command: with_secret GITHUB_TOKEN=github_token -- gh repo list"

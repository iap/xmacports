#!/bin/bash
# Secret management tests (SOPS + age)
# shellcheck disable=SC2015

set -u

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
export DOTFILES_ROOT
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

echo "SOPS + age Secret Management Tests"
date '+%Y-%m-%d %H:%M:%S'
echo

echo "1. Prerequisites"
check "sops is installed" command -v sops
check "age is installed" command -v age
check "python3 is installed" command -v python3
echo

echo "2. File structure"
check "secrets/enc.yaml exists" test -f "$DOTFILES_ROOT/secrets/secrets.enc.yaml"
check "secrets.yaml is gitignored" test -f "$DOTFILES_ROOT/secrets/secrets.yaml" || true
check ".sops.yaml exists" test -f "$DOTFILES_ROOT/.sops.yaml"
echo

echo "3. SOPS configuration"
if [ -f "$DOTFILES_ROOT/.sops.yaml" ]; then
  check "age public key is present in .sops.yaml" grep -qE 'age: +age1' "$DOTFILES_ROOT/.sops.yaml"
  check "path_regex matches secrets/enc.yaml" grep -q 'path_regex:.*enc' "$DOTFILES_ROOT/.sops.yaml"
  PUBLIC_KEY=$(grep -E 'age: +age1' "$DOTFILES_ROOT/.sops.yaml" | sed 's/.*age: *//' | tr -d ' ')
  if command -v age > /dev/null 2>&1; then
    AGE_KEYS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"
    if [ -f "$AGE_KEYS_FILE" ]; then
      EXTRACTED_KEY=$(age-keygen -y "$AGE_KEYS_FILE" 2> /dev/null | grep -E '^age1' | head -1)
      check "public key in .sops.yaml matches local age keypair" [ "$PUBLIC_KEY" = "$EXTRACTED_KEY" ]
    else
      echo "   SKIP: age private key not found at $AGE_KEYS_FILE"
    fi
  fi
else
  echo "   SKIP: .sops.yaml absent"
fi
echo

echo "4. Encrypted file integrity"
if [ -f "$DOTFILES_ROOT/secrets/secrets.enc.yaml" ] && command -v sops > /dev/null 2>&1; then
  check "secrets.enc.yaml decrypts without error" sops -d "$DOTFILES_ROOT/secrets/secrets.enc.yaml" > /dev/null 2>&1
  check "secrets.enc.yaml contains valid YAML when decrypted" sops -d "$DOTFILES_ROOT/secrets/secrets.enc.yaml" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" 2> /dev/null
else
  echo "   SKIP: sops or encrypted file missing"
fi
echo

echo "5. Secret functions"
if [ -f "$DOTFILES_ROOT/shared/functions.sh" ]; then
  check "secret function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f secret > /dev/null'
  check "secret_list function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f secret_list > /dev/null'
  check "with_secret function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f with_secret > /dev/null'
  check "secrets_decrypt function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f secrets_decrypt > /dev/null'
  check "secrets_encrypt function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f secrets_encrypt > /dev/null'
  check "secrets_edit function is defined" bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && declare -f secrets_edit > /dev/null'
else
  echo "   SKIP: shared/functions.sh absent"
fi
echo

echo "6. Keybase removal"
if [ -f "$DOTFILES_ROOT/shared/functions.sh" ]; then
  if bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && ! declare -f _secret_kvstore > /dev/null'; then
    pass "no _secret_kvstore function"
  else
    fail "no _secret_kvstore function"
  fi
  if bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && ! declare -f _secret_kbfs > /dev/null'; then
    pass "no _secret_kbfs function"
  else
    fail "no _secret_kbfs function"
  fi
  if bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && ! declare -f secret_set > /dev/null'; then
    pass "no secret_set function"
  else
    fail "no secret_set function"
  fi
  if bash -c 'source "$DOTFILES_ROOT/shared/functions.sh" && ! declare -f secret_del > /dev/null'; then
    pass "no secret_del function"
  else
    fail "no secret_del function"
  fi
else
  echo "   SKIP: shared/functions.sh absent"
fi
echo

TOTAL=$((PASSED + FAILED))
echo "────────────────────────────────"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "✅ All secret tests passed!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

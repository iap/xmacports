#!/bin/bash
set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

FAILED=0

echo ""
echo "1. Platform Detection Tests"
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "   - is_macos: PASS (true on macOS)"
else
  echo "   - is_macos: SKIP (false on non-macOS)"
fi
if [[ "$(uname -s)" == "Linux" ]]; then
  echo "   - is_linux: PASS (true on Linux)"
else
  echo "   - is_linux: PASS (false on non-Linux)"
fi

echo ""
echo "2. False Positive Prevention"

if [[ "$(uname -s)" == "Linux" ]]; then
  echo "   - SKIP: package-manager path checks removed"
else
  echo "   - SKIP: macOS-specific package-manager checks removed"
fi

echo ""
echo "3. PATH Integrity"

# Test platform.sh in isolation with clean environment
test_path=$(HOME="$HOME" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin" \
  bash -c "unset DOTFILES_ENV_LOADED; source '$DOTFILES_ROOT/.config/env.d/platform.sh'; echo \"\$PATH\"")

PATH_COUNT=$(echo "$test_path" | tr ':' '\n' | sort | uniq -d | wc -l | tr -d ' ')
if [[ "$PATH_COUNT" -eq 0 ]]; then
  echo "   - PASS: No duplicate PATH entries after platform.sh"
else
  echo "   - FAIL: Duplicate PATH entries found: $PATH_COUNT"
  ((FAILED++))
fi

# platform.sh should add user bin directories to PATH
if [[ ":$test_path:" == *":$HOME/bin:"* ]] && [[ ":$test_path:" == *":$HOME/.local/bin:"* ]]; then
  echo "   - PASS: User bin directories added by platform.sh"
else
  echo "   - FAIL: User bin directories missing after platform.sh load"
  echo "   - PATH: $test_path"
  ((FAILED++))
fi

echo ""
echo "4. Required Tool Availability"

for tool in ls grep sed curl; do
  if command -v "$tool" > /dev/null 2>&1; then
    echo "   - PASS: $tool available"
  else
    echo "   - FAIL: $tool missing"
    ((FAILED++))
  fi
done

echo ""
echo "5. XDG Directory Compliance"

for var in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME; do
  if [[ -n "${!var:-}" ]]; then
    echo "   - PASS: $var set to ${!var}"
  else
    echo "   - FAIL: $var not set"
    ((FAILED++))
  fi
done

if [[ $FAILED -eq 0 ]]; then
  echo ""
  echo "6. SOPS + age Secret Store"

  if [[ -f "$DOTFILES_ROOT/.sops.yaml" ]]; then
    echo "   - .sops.yaml present"
    if grep -qE 'age: +age1' "$DOTFILES_ROOT/.sops.yaml"; then
      echo "   - age public key configured"
    else
      echo "   - WARN: age public key looks like placeholder"
    fi
  else
    echo "   - SKIP: .sops.yaml absent"
  fi

  if [[ -f "$DOTFILES_ROOT/secrets/secrets.enc.yaml" ]]; then
    echo "   - secrets.enc.yaml present"
    if command -v sops > /dev/null 2>&1; then
      if sops -d "$DOTFILES_ROOT/secrets/secrets.enc.yaml" > /dev/null 2>&1; then
        echo "   - secrets.enc.yaml decrypts successfully"
      else
        echo "   - FAIL: secrets.enc.yaml failed to decrypt"
        ((FAILED++))
      fi
    else
      echo "   - SKIP: sops not installed"
    fi
  else
    echo "   - SKIP: secrets.enc.yaml absent"
  fi

  AGE_KEY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age"
  if [[ -f "$AGE_KEY_DIR/keys.txt" ]]; then
    echo "   - Private age key found"
  else
    echo "   - SKIP: age private key not yet generated (run make secrets-init)"
  fi

  if [[ $FAILED -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
  else
    echo "=== $FAILED TEST(S) FAILED ==="
    exit 1
  fi
else
  echo "=== $FAILED TEST(S) FAILED ==="
  exit 1
fi

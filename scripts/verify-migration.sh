#!/bin/bash
# Migration Verification Script
# Run after mise/MacPorts changes to validate zero false positives

set -euo pipefail

FAILURES=0
WARNINGS=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "✅ $name"
  else
    echo "❌ $name"
    ((FAILURES++))
  fi
}

warn() {
  local name="$1"
  shift
  if "$@"; then
    echo "✅ $name"
  else
    echo "⚠️  $name"
    ((WARNINGS++))
  fi
}

echo "=== Migration Verification ==="
echo

# 1. PATH precedence checks
check "mise global shims in PATH" bash -c '
  source ~/.dotfiles/.config/env.d/platform.sh
  echo "$PATH" | grep -q "mise"
'

check "mise project tools available in PATH" bash -c '
  source ~/.dotfiles/.config/env.d/platform.sh
  command -v shellcheck >/dev/null &&
  command -v shfmt >/dev/null &&
  command -v age >/dev/null &&
  command -v sops >/dev/null
'

check "MacPorts system tools available" bash -c '
  command -v git >/dev/null &&
  command -v gpg >/dev/null &&
  command -v python3 >/dev/null &&
  command -v jq >/dev/null &&
  command -v rg >/dev/null
'

# 2. Version checks (exact match required)
check "shellcheck version 0.10.0" bash -c '
  shellcheck --version 2>&1 | grep -q "version: 0.10.0"
'

check "shfmt version 3.8.0" bash -c '
  shfmt --version 2>&1 | grep -q "v3.8.0"
'

check "age version 1.2.1" bash -c '
  age --version 2>&1 | grep -q "1.2.1"
'

check "sops version 3.9.4" bash -c '
  sops --version 2>&1 | grep -q "3.9.4"
'

# 3. Global runtimes
check "python via mise (uv)" bash -c '
  source ~/.dotfiles/.config/env.d/platform.sh
  PATH="$HOME/.local/share/mise/shims:$PATH" python3 --version 2>&1 | grep -q "3.12"
'
check "pnpm via mise" bash -c '
  source ~/.dotfiles/.config/env.d/platform.sh
  PATH="$HOME/.local/share/mise/shims:$PATH" pnpm --version 2>&1 | grep -q "9"
'
check "uv via mise" bash -c '
  source ~/.dotfiles/.config/env.d/platform.sh
  PATH="$HOME/.local/share/mise/shims:$PATH" uv --version 2>&1 | grep -q "0.5"
'

# 4. Shell integration
check "ZSH loads mise shims" bash -c '
  zsh -c "source ~/.zshrc; command -v shellcheck" 2>&1 | grep -q "mise"
'
check "Bash loads mise shims" bash -c '
  bash -c "source ~/.bashrc; command -v shellcheck" 2>&1 | grep -q "mise"
'

# 5. CI workflow
check "CI installs mise tools directly" bash -c '
  grep -q "mise install" ~/.dotfiles/.github/workflows/test.yml
'

# 6. Test suite
check "make test-all passes" bash -c '
  cd ~/.dotfiles && make test-all >/dev/null 2>&1
'
check "make shellcheck passes" bash -c '
  cd ~/.dotfiles && make shellcheck >/dev/null 2>&1
'
check "make test-compliance passes" bash -c '
  cd ~/.dotfiles && make test-compliance >/dev/null 2>&1
'
check "make audit passes" bash -c '
  cd ~/.dotfiles && make audit >/dev/null 2>&1
'

# 7. GPG/SSH
check "GPG agent SSH auth works" bash -c '
  ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"
'

# 8. Secrets
check "SOPS decryption works" bash -c '
  cd ~/.dotfiles && sops -d secrets/secrets.enc.yaml >/dev/null 2>&1
'

# 9. Bootstrap idempotency
check "bootstrap.sh runs idempotently" bash -c '
  cd ~/.dotfiles && ./bootstrap.sh >/dev/null 2>&1 && ./bootstrap.sh >/dev/null 2>&1
'

# 10. MacPorts cleanup check (warn only)
warn "shellcheck not in MacPorts" bash -c '! port installed shellcheck 2>/dev/null | grep -q "active"'
warn "shfmt not in MacPorts" bash -c '! port installed shfmt 2>/dev/null | grep -q "active"'
warn "age not in MacPorts" bash -c '! port installed age 2>/dev/null | grep -q "active"'
warn "sops not in MacPorts" bash -c '! port installed sops 2>/dev/null | grep -q "active"'

echo
echo "=== Summary ==="
if [[ $FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
  echo "🎉 All verification checks passed!"
  exit 0
elif [[ $FAILURES -eq 0 ]]; then
  echo "⚠️  $WARNINGS warning(s) - MacPorts cleanup pending"
  exit 0
else
  echo "❌ $FAILURES failure(s), $WARNINGS warning(s)"
  exit 1
fi

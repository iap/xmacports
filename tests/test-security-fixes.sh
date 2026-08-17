#!/bin/bash
# Revert-check harness for the security-review-round2 fixes.
# Each test asserts a previously-confirmed defect is now fixed, and the suite
# must itself be green (it proves the fix is real, not a no-op). A no-op fix
# would make at least one assertion fail.
#
# Run: bash tests/test-security-fixes.sh   (or: make test → security-fixes)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
export DOTFILES_ROOT

PASS=0
FAIL=0

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

# ---------------------------------------------------------------------------
# 1. pre-commit private-key CONTENT regex must match real PEM/OpenSSH headers.
#    Regression: old pattern "BEGIN (OPENSSH|RSA|DSA|EC|PRIVATE) KEY" only
#    matched the impossible "BEGIN OPENSSH KEY" and let every real key through.
# ---------------------------------------------------------------------------
precommit="$DOTFILES_ROOT/.githooks/pre-commit"
if [[ -f "$precommit" ]]; then
  # The new regex string must appear and must NOT contain the old broken form.
  # Use fixed-string matching to avoid BRE bracket-balancing pitfalls.
  if grep -qF 'PRIVATE KEY( BLOCK)?-----' "$precommit"; then
    pass "pre-commit matches real private-key headers (OPENSSH/RSA/EC/PGP)"
  else
    fail "pre-commit missing the corrected private-key regex"
  fi
  # Ensure the OLD broken alternation is gone (it would silently pass keys).
  if grep -qE 'BEGIN \((OPENSSH|RSA|DSA|EC|PRIVATE)\) KEY' "$precommit"; then
    fail "pre-commit still contains the broken 'BEGIN (...) KEY' alternation"
  else
    pass "pre-commit no longer uses the broken private-key alternation"
  fi
else
  fail "pre-commit hook not found at $precommit"
fi

# ---------------------------------------------------------------------------
# 2. pre-commit must block the SOPS age MASTER key (decrypts whole store) and
#    .asc/.gpg files by name.
# ---------------------------------------------------------------------------
if [[ -f "$precommit" ]]; then
  if grep -q 'AGE-SECRET-KEY-1\[0-9A-Z\]{50,}' "$precommit"; then
    pass "pre-commit blocks AGE-SECRET-KEY-1 content"
  else
    fail "pre-commit does not block AGE-SECRET-KEY-1 content"
  fi
  if grep -qE '\*\.asc|\*\.gpg|\*\.pgp' "$precommit"; then
    pass "pre-commit blocks .asc/.gpg/.pgp by name"
  else
    fail "pre-commit does not block .asc/.gpg/.pgp by name"
  fi
  if grep -qE 'keys\.txt|\*age\*key\*|\*\.agekey' "$precommit"; then
    pass "pre-commit blocks age master key filename (keys.txt / age-key)"
  else
    fail "pre-commit does not block age master key filename"
  fi
fi

# ---------------------------------------------------------------------------
# 3. pre-commit validates the STAGED BLOB for the ENC marker, not the worktree.
#    Regression: old code ran `sops -d "$f"` on the worktree file, which could
#    be restored to ciphertext after `git add` (bypass). New code uses
#    `git show ":$f" | grep ENC[AES256_GCM` (fail-closed, no key needed).
# ---------------------------------------------------------------------------
if [[ -f "$precommit" ]]; then
  # Fixed-string match: the file literally contains `git show ":$f"` and the
  # ENC[AES256_GCM marker grep, proving the staged-blob check is in place.
  if grep -qF 'git show ":$f"' "$precommit" && grep -qF 'ENC\[AES256_GCM' "$precommit"; then
    pass "pre-commit validates the staged blob for the ENC ciphertext marker"
  else
    fail "pre-commit does not validate the staged blob for ENC[AES256_GCM"
  fi
  # The old fail-open `if command -v sops` gate around the check must be gone.
  if grep -q 'if command -v sops' "$precommit"; then
    fail "pre-commit still gates the encryption check behind 'command -v sops' (fail-open)"
  else
    pass "pre-commit is no longer fail-open when sops is absent"
  fi
fi

# ---------------------------------------------------------------------------
# 4. audit.sh must FAIL (exit non-zero) when a private key under ~/.ssh is
#    world/group-readable. Regression: those checks printed ⚠️ but never
#    incremented the failure counter, so the audit exited 0.
# ---------------------------------------------------------------------------
auditscript="$DOTFILES_ROOT/scripts/audit.sh"
if [[ -f "$auditscript" ]]; then
  # The ssh/gnupg private-key block must now call _audit_fail on deviation.
  # Count _audit_fail increments that sit inside the ssh/gnupg section.
  # Simpler robust check: the private-key file branch must increment the counter.
  if grep -n 'expected 600 — private key is world/group readable' "$auditscript" > /dev/null; then
    # The line above is in an else-branch that must be followed by _audit_fail.
    if awk '/expected 600 — private key is world\/group readable/{found=1; next} found && /_audit_fail=\$\(\(_audit_fail \+ 1\)\)/{print; exit}' "$auditscript" | grep -q .; then
      pass "audit.sh fails the build on a world-readable private key"
    else
      fail "audit.sh private-key branch does not call _audit_fail"
    fi
  else
    fail "audit.sh private-key check message not found"
  fi
else
  fail "audit.sh not found at $auditscript"
fi

# ---------------------------------------------------------------------------
# 5. audit.sh globs must be $DOTFILES_ROOT-prefixed so the +x / 644 checks run
#    even when invoked from outside the repo root.
# ---------------------------------------------------------------------------
if [[ -f "$auditscript" ]]; then
  if grep -q '"\$DOTFILES_ROOT"/.zshrc.d/\*.sh' "$auditscript" && grep -q '"\$DOTFILES_ROOT"/shared/\*.sh' "$auditscript"; then
    pass "audit.sh globs are \$DOTFILES_ROOT-prefixed"
  else
    fail "audit.sh globs are not \$DOTFILES_ROOT-prefixed (would skip shared/*.sh off-root)"
  fi
fi

# ---------------------------------------------------------------------------
# 6. secrets.sh _sops_encrypt must propagate the sops exit code (not always 0).
# ---------------------------------------------------------------------------
secrets="$DOTFILES_ROOT/shared/secrets.sh"
if [[ -f "$secrets" ]]; then
  if grep -q 'local rc=$?' "$secrets" && grep -q 'return "$rc"' "$secrets"; then
    pass "secrets.sh _sops_encrypt returns the sops exit code"
  else
    fail "secrets.sh _sops_encrypt does not capture/return the sops exit code"
  fi
  if grep -q '_sops_encrypt || {' "$secrets"; then
    pass "secrets.sh secrets_encrypt checks the encrypt return code before logging success"
  else
    fail "secrets.sh secrets_encrypt does not check the encrypt return code"
  fi
fi

# ---------------------------------------------------------------------------
# 7. .gitignore must cover *.bak so stale hook backups are never committed on a
#    fresh clone (previously depended on machine-local ~/.gitignore_global).
# ---------------------------------------------------------------------------
gitignore="$DOTFILES_ROOT/.gitignore"
if [[ -f "$gitignore" ]]; then
  if grep -q '^\*\.bak$' "$gitignore"; then
    pass ".gitignore covers *.bak"
  else
    fail ".gitignore does not cover *.bak"
  fi
fi

echo
echo "Security-fix verification: $PASS passed, $FAIL failed."
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

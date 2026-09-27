#!/bin/bash
# Regression test for the recipient guard in scripts/secrets-init.sh.
#
# The guard must, when rotating a key:
#   (a) proceed on a single-recipient policy and rewrite that recipient;
#   (b) refuse to rewrite a policy that already lists more than one recipient
#       (the list is comma-separated on one line, so a line count under-reports)
#       and leave it untouched; and
#   (c) treat a key merely named in an inline comment as NOT a recipient.
#
# The real script is run against hermetic fixtures with stubbed age/sops/python3,
# so these are behaviour checks, not pattern greps -- an equivalent rewrite of
# the guard keeps the test green.
set -u

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$DOTFILES_ROOT/scripts/secrets-init.sh"

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

if [[ ! -f "$SRC" ]]; then
  echo "FAIL: $SRC not found"
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-secrets-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

K1=age1gptsedytxyrn7havhaf82fexlml3jque7g85w6ewgyapcjetyddqwxnmft
K2=age1ue7gpf83k73edhd6u379jwcgxcde8s3e8kpxl4ema3rhmj74xpkqcccqnl
NEW=age1stubstubstubstubstubstubstubstubstubstubstubstubstubstubstub

# Stubs so the script runs anywhere: a deterministic "keypair" plus no-op
# age/sops/python3 (the guard logic under test needs none of them for real).
STUB="$TMP/bin"
mkdir -p "$STUB"
cat > "$STUB/age-keygen" << 'STUBEOF'
#!/bin/sh
case "${1:-}" in
  -o) printf '%s\n' 'AGE-SECRET-KEY-1STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB' > "$2" ;;
  -y) printf '%s\n' 'age1stubstubstubstubstubstubstubstubstubstubstubstubstubstubstub' ;;
esac
STUBEOF
chmod +x "$STUB/age-keygen"
for t in age sops python3; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB/$t"
  chmod +x "$STUB/$t"
done

# run_guard <case-dir> : lay out a hermetic DOTFILES_ROOT + HOME and run the script.
run_guard() {
  local root="$1"
  mkdir -p "$root/scripts" "$root/secrets" "$root/home/.config"
  cp "$SRC" "$root/scripts/secrets-init.sh"
  printf 'dotfiles:\n  probe: value\n' > "$root/secrets/secrets.yaml"
  PATH="$STUB:$PATH" HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
    DOTFILES_ROOT="$root" bash "$root/scripts/secrets-init.sh" > "$root/out.txt" 2>&1
}

echo "Secrets-init recipient guard tests"
echo

# --- (a) single recipient: proceed and rewrite it ---
echo "(a) single-recipient policy"
A="$TMP/a"
mkdir -p "$A"
printf 'creation_rules:\n  - path_regex: secrets/[^.]*\\.yaml$\n    age: %s\n' "$K1" > "$A/.sops.yaml"
if run_guard "$A"; then
  pass "rotating a single-recipient policy succeeds"
else
  fail "single-recipient rotation exited non-zero: [$(cat "$A/out.txt")]"
fi
if grep -q "age: $NEW" "$A/.sops.yaml"; then pass "the single recipient is rewritten to the new key"; else fail "the recipient was not rewritten: [$(cat "$A/.sops.yaml")]"; fi
if grep -q "$K1" "$A/.sops.yaml"; then fail "the old recipient is still present"; else pass "the old recipient is replaced"; fi
echo

# --- (b) two recipients on one line: refuse and leave untouched ---
echo "(b) multi-recipient policy"
B="$TMP/b"
mkdir -p "$B"
printf 'creation_rules:\n  - path_regex: secrets/[^.]*\\.yaml$\n    age: %s,%s\n' "$K1" "$K2" > "$B/.sops.yaml"
before="$(cat "$B/.sops.yaml")"
if run_guard "$B"; then
  fail "the script did not refuse a multi-recipient policy (exit 0)"
else
  pass "a multi-recipient policy is refused"
fi
if grep -qi 'refus' "$B/out.txt"; then pass "the refusal explains why it stopped"; else fail "refusal message missing: [$(cat "$B/out.txt")]"; fi
if [ "$(cat "$B/.sops.yaml")" = "$before" ]; then pass "the multi-recipient policy is left unchanged"; else fail "the policy was modified"; fi
if grep -q "$K2" "$B/.sops.yaml"; then pass "the second (recovery) recipient is preserved"; else fail "the second recipient was dropped"; fi
echo

# --- (c) a key named only in an inline comment is not a recipient ---
echo "(c) single recipient with a commented key"
C="$TMP/c"
mkdir -p "$C"
printf 'creation_rules:\n  - path_regex: secrets/[^.]*\\.yaml$\n    age: %s  # recovery: %s\n' "$K1" "$K2" > "$C/.sops.yaml"
if run_guard "$C"; then
  pass "a commented key is not counted as a recipient (rotation proceeds)"
else
  fail "a commented key was miscounted as a second recipient: [$(cat "$C/out.txt")]"
fi
echo

echo "────────────────────────────────"
echo "Total: $((PASSED + FAILED))  Passed: $PASSED  Failed: $FAILED"
[ "$FAILED" -eq 0 ] && echo "✅ All secrets-init guard tests passed!" && exit 0 || {
  echo "WARN: $FAILED test(s) failed."
  exit 1
}

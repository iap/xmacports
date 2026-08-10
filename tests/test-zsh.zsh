#!/usr/bin/env zsh
# zsh load-chain smoke test.
#
# The dotfiles load chain is exercised in CI only under bash (tests/run-tests.sh
# is a bash runner). But .zshrc sources shared/*.sh under zsh, and shared/prompt.sh
# defines the zsh-only renderer _prompt_render_zsh. A zsh-path regression (e.g. a
# bashism that parses under bash but breaks under zsh, or a broken zsh glob/source)
# would ship green. This test replicates .zshrc's exact load chain under a real
# zsh and asserts the result is sane.
#
# It sources the SAME files .zshrc sources (minus $HOME/.profile / env.d / local
# overlays, which are host-specific) using DOTFILES_ROOT so it is deterministic in
# CI and locally. Exits 1 if any source errors or any invariant is missing.

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

# check <desc> <command...> — run a command; pass if it exits 0.
check() {
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

echo "Dotfiles zsh Load-Chain Smoke Test"
echo "DOTFILES_ROOT: $DOTFILES_ROOT"
echo

# 1. Source the load chain exactly as .zshrc does (platform is the single
#    source of truth; the rest are functions, secrets, prompt, aliases).
echo "1. Load chain sources cleanly under zsh"
_load_ok=1
if ! source "$DOTFILES_ROOT/shared/platform.sh"; then
  echo "FAIL: error sourcing shared/platform.sh under zsh"
  _load_ok=0
fi
for _f in "$DOTFILES_ROOT"/shared/*.sh; do
  [ -f "$_f" ] || continue
  source "$_f" 2> /dev/null || {
    echo "FAIL: error sourcing $_f under zsh"
    _load_ok=0
  }
done
for _f in "$DOTFILES_ROOT"/.zshrc.d/*.sh; do
  [ -f "$_f" ] || continue
  source "$_f" 2> /dev/null || {
    echo "FAIL: error sourcing $_f under zsh"
    _load_ok=0
  }
done
unset _f
[ "$_load_ok" -eq 1 ] && pass "shared/*.sh and .zshrc.d/*.sh source cleanly under zsh" ||
  fail "one or more files failed to source under zsh"
echo

# 2. Key functions defined after the load chain (platform, functions, secrets, prompt).
echo "2. Functions defined under zsh"
check "is_macos defined (platform.sh)" command -v is_macos > /dev/null 2>&1
check "short_pwd defined (prompt.sh via functions.sh)" command -v short_pwd > /dev/null 2>&1
check "secret defined (secrets.sh)" command -v secret > /dev/null 2>&1
check "_prompt_render_zsh defined (zsh renderer)" command -v _prompt_render_zsh > /dev/null 2>&1
echo

# 3. Environment built correctly under zsh — catches the classic zsh
#    word-splitting regression in path_dedupe / path_prepend_if_present.
echo "3. Environment built under zsh"
check "XDG_CONFIG_HOME set" [ -n "${XDG_CONFIG_HOME:-}" ]
check "PATH built and non-empty" [ -n "${PATH:-}" ]
# mise is optional (per MANUAL.md). platform.sh only prepends shims when mise
# exists, so assert shims are present ONLY if mise is installed; a mise-less
# environment with no shim dir is the expected, correct state — not a failure.
if command -v mise > /dev/null 2>&1; then
  check "mise shims present in PATH (mise installed)" sh -c 'printf "%s" "$PATH" | grep -qF ".local/share/mise/shims"'
else
  echo "PASS: mise not installed — skipping shim check (optional, graceful no-shim expected)"
  PASSED=$((PASSED + 1))
fi
echo

# 4. zsh renderer actually produces output (exercises zsh-specific branch).
echo "4. zsh prompt renderer executes"
_check_render=$(_prompt_render_zsh 0 2> /dev/null)
check "_prompt_render_zsh returns a prompt string" [ -n "$_check_render" ]
echo

if [ "$FAILED" -gt 0 ]; then
  echo "❌ zsh smoke test failed: $FAILED failure(s), $PASSED passed."
  exit 1
fi
echo "🎉 zsh smoke test passed ($PASSED checks)."
exit 0

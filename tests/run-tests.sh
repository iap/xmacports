#!/bin/bash
# Test runner

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
export DOTFILES_ROOT

echo "Dotfiles Test Runner"
echo "Project root: $DOTFILES_ROOT"
echo "Test directory: $SCRIPT_DIR"
echo

check_prerequisites() {
  echo "Checking prerequisites..."

  # Check if dotfiles are bootstrapped (or DOTFILES_ROOT is set)
  if [[ -n "${DOTFILES_ROOT:-}" ]] && [[ -d "$DOTFILES_ROOT" ]]; then
    echo "✅ Using DOTFILES_ROOT=$DOTFILES_ROOT (no symlinks required)"
  elif [[ -L "$HOME/.bashrc" ]]; then
    echo "✅ Dotfiles appear to be bootstrapped"
  else
    echo "⚠️  Dotfiles don't appear to be bootstrapped."
    echo "   Run 'make bootstrap' first, or set DOTFILES_ROOT=/path/to/repo to test without symlinks."
    return 1
  fi

  # Check if required commands are available
  local missing_commands=()
  for cmd in git zsh bash; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      missing_commands+=("$cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    echo "⚠️  Missing required commands: ${missing_commands[*]}"
    return 1
  fi

  echo "✅ Prerequisites check passed"
  return 0
}

run_function_tests() {
  echo "Running function tests..."
  if [[ -f "$SCRIPT_DIR/test-functions.sh" ]]; then
    bash "$SCRIPT_DIR/test-functions.sh"
  else
    echo "❌ test-functions.sh not found"
    return 1
  fi
}

run_config_tests() {
  echo "Running configuration tests..."
  if [[ -f "$SCRIPT_DIR/test-bootstrap.sh" ]]; then
    bash "$SCRIPT_DIR/test-bootstrap.sh"
  else
    echo "❌ test-bootstrap.sh not found"
    return 1
  fi
}

run_secrets_tests() {
  echo "Running secret management tests..."
  if [[ -f "$SCRIPT_DIR/test-secrets.sh" ]]; then
    bash "$SCRIPT_DIR/test-secrets.sh"
  else
    echo "❌ test-secrets.sh not found"
    return 1
  fi
}

run_hook_tests() {
  echo "Running git hook tests..."
  if [[ -f "$SCRIPT_DIR/test-pre-push-hook.sh" ]]; then
    bash "$SCRIPT_DIR/test-pre-push-hook.sh"
  else
    echo "❌ test-pre-push-hook.sh not found"
    return 1
  fi
}

# Revert-check harness for the review-findings fixes. Asserts each verified
# bug is actually fixed and that no false-positive regression was introduced.
run_review_fix_tests() {
  echo "Running review-fix verification tests..."
  if [[ -f "$SCRIPT_DIR/test-review-fixes.sh" ]]; then
    bash "$SCRIPT_DIR/test-review-fixes.sh"
  else
    echo "❌ test-review-fixes.sh not found"
    return 1
  fi
}

run_security_fix_tests() {
  echo "Running security-fix verification tests..."
  if [[ -f "$SCRIPT_DIR/test-security-fixes.sh" ]]; then
    bash "$SCRIPT_DIR/test-security-fixes.sh"
  else
    echo "❌ test-security-fixes.sh not found"
    return 1
  fi
}

# test-bootstrap.sh IS the bootstrap idempotency suite; `config` and `bootstrap`
# are two names for the same checks. Kept as an alias so `run-tests.sh bootstrap`
# stays valid, but the `all` path invokes it once via run_config_tests.
run_bootstrap_idempotency_tests() {
  run_config_tests
}

run_compliance_tests() {
  echo "Running compliance checks..."
  check_prerequisites && run_config_tests && bash "$DOTFILES_ROOT/scripts/compliance-check.sh"
}

# Main test execution
main() {
  local test_type="${1:-all}"

  case "$test_type" in
    "functions")
      check_prerequisites && run_function_tests
      ;;
    "config")
      check_prerequisites && run_config_tests
      ;;
    "secrets")
      check_prerequisites && run_secrets_tests
      ;;
    "hooks")
      check_prerequisites && run_hook_tests
      ;;
    "review-fixes")
      check_prerequisites && run_review_fix_tests
      ;;
    "security-fixes")
      check_prerequisites && run_security_fix_tests
      ;;
    "bootstrap")
      check_prerequisites && run_bootstrap_idempotency_tests
      ;;
    "compliance")
      check_prerequisites && run_compliance_tests
      ;;
    "all" | "")
      echo "Running complete test suite..."
      echo

      if ! check_prerequisites; then
        exit 1
      fi

      echo "1. Configuration Tests"
      echo

      run_config_tests
      cfg_status=$?
      echo

      echo "2. Function Tests"
      echo

      run_function_tests
      fn_status=$?
      echo

      echo "3. Secret Management Tests"
      echo

      run_secrets_tests
      sec_status=$?
      echo

      echo "4. Git Hook Tests"
      echo

      run_hook_tests
      hook_status=$?
      echo

      echo "5. Review-Fix Verification Tests"
      echo

      run_review_fix_tests
      review_status=$?
      echo

      echo "6. Security-Fix Verification Tests"
      echo

      run_security_fix_tests
      secfix_status=$?
      echo

      if ((cfg_status != 0 || fn_status != 0 || sec_status != 0 || hook_status != 0 || review_status != 0 || secfix_status != 0)); then
        echo "❌ Test suite completed with failures"
        exit 1
      fi

      echo "🎉 Complete test suite finished!"
      ;;
    "help" | "-h" | "--help")
      echo "Usage: $0 [test_type]"
      echo
      echo "Test types:"
      echo "  all         Run all tests (default)"
      echo "  config      Run configuration tests only"
      echo "  functions   Run function tests only"
      echo "  secrets     Run secret management tests only"
      echo "  review-fixes Run review-finding verification tests only"
      echo "  security-fixes Run security-fix verification tests only"
      echo "  bootstrap   Run bootstrap idempotency tests only"
      echo "  compliance  Run configuration plus compliance checks"
      echo "  help        Show this help message"
      ;;
    *)
      echo "❌ Unknown test type: $test_type"
      echo "Run '$0 help' for available options"
      exit 1
      ;;
  esac
}

main "$@"

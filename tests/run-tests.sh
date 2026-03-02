#!/bin/bash
# Test runner for dotfiles project
# Provides organized test execution and reporting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Dotfiles Test Runner"
echo "Project root: $DOTFILES_ROOT"
echo "Test directory: $SCRIPT_DIR"
echo

# Check prerequisites
check_prerequisites() {
  echo "Checking prerequisites..."

  # Check if dotfiles are bootstrapped
  if [[ ! -L "$HOME/.zshrc" ]]; then
    echo "⚠️  Dotfiles don't appear to be bootstrapped. Run 'make bootstrap' first."
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

# Run function tests
run_function_tests() {
  echo "Running function tests..."
  if [[ -f "$SCRIPT_DIR/test-functions.sh" ]]; then
    bash "$SCRIPT_DIR/test-functions.sh"
  else
    echo "❌ test-functions.sh not found"
    return 1
  fi
}

# Run compliance tests
run_compliance_tests() {
  echo "Running compliance tests..."
  if [[ -f "$DOTFILES_ROOT/scripts/compliance-check.sh" ]]; then
    bash "$DOTFILES_ROOT/scripts/compliance-check.sh"
  else
    echo "❌ compliance-check.sh not found"
    return 1
  fi
}

# Run configuration tests
run_config_tests() {
  echo "Running configuration tests..."
  cd "$DOTFILES_ROOT" || {
    echo "❌ Failed to change to dotfiles directory"
    return 1
  }
  make test
}

# Main test execution
main() {
  local test_type="${1:-all}"

  case "$test_type" in
    "functions")
      check_prerequisites && run_function_tests
      ;;
    "compliance")
      check_prerequisites && run_compliance_tests
      ;;
    "config")
      check_prerequisites && run_config_tests
      ;;
    "all" | "")
      echo "Running complete test suite..."
      echo

      if ! check_prerequisites; then
        exit 1
      fi

      echo "1. Configuration Tests"
      echo ""
      run_config_tests
      echo

      echo "2. Compliance Tests"
      echo ""
      run_compliance_tests
      echo

      echo "3. Function Tests"
      echo ""
      run_function_tests

      echo
      echo "🎉 Complete test suite finished!"
      ;;
    "help" | "-h" | "--help")
      echo "Usage: $0 [test_type]"
      echo
      echo "Test types:"
      echo "  all         Run all tests (default)"
      echo "  functions   Run function tests only"
      echo "  compliance  Run compliance tests only"
      echo "  config      Run configuration tests only"
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

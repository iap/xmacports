#!/bin/bash
# Test runner

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${DOTFILES_ROOT:-$(dirname "$SCRIPT_DIR")}"
export DOTFILES_ROOT
DOTFILES="$HOME/.dotfiles"

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
    "config")
      check_prerequisites && run_config_tests
      ;;
    "compliance")
      check_prerequisites && run_config_tests && DOTFILES_ROOT="$DOTFILES_ROOT" bash "$DOTFILES_ROOT/scripts/compliance-check.sh"
      ;;
    "all" | "")
      echo "Running complete test suite..."
      echo

      if ! check_prerequisites; then
        exit 1
      fi

      echo "1. Configuration Tests"
      echo
      run_config_tests || true
      echo

      echo "2. Function Tests"
      echo
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
      echo "  config      Run configuration tests only"
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

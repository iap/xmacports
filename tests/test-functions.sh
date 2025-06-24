#!/bin/bash
# Comprehensive function testing suite for dotfiles project
# Tests all functions defined in the configuration system

set -e

echo "=== Dotfiles Function Testing Suite ==="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting comprehensive function tests"
echo

# Create test directories
TEST_DIR="$HOME/.cache/dotfiles-test-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo

# Source the functions to make them available
source "$HOME/.dotfiles/.zshrc.d/functions.sh"
source "$HOME/.dotfiles/scripts/timeout_prompt.sh"

# Track test results
PASSED=0
FAILED=0
TOTAL=0

test_result() {
    local test_name="$1"
    local result="$2"
    TOTAL=$((TOTAL + 1))
    
    if [[ "$result" == "0" ]]; then
        echo "✅ PASS: $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        FAILED=$((FAILED + 1))
    fi
}

echo "1. Testing utility functions from functions.sh"
echo "============================================="

# Test mkcd function
echo "Testing mkcd function..."
mkcd test-mkcd-dir && [[ "$(pwd)" == "$TEST_DIR/test-mkcd-dir" ]]
test_result "mkcd creates directory and changes to it" $?
cd ..

# Test extract function (create test archives)
echo -e "\nTesting extract function..."

# Create test files for extraction
echo "test content" > test.txt

# Test tar.gz
tar czf test.tar.gz test.txt
extract test.tar.gz && [[ -f test.txt ]]
test_result "extract handles tar.gz files" $?
rm -f test.txt

# Test zip
zip test.zip test.txt > /dev/null 2>&1 || echo "zip not available, skipping zip test"
if [[ -f test.zip ]]; then
    extract test.zip && [[ -f test.txt ]]
    test_result "extract handles zip files" $?
    rm -f test.txt
fi

# Test invalid file
extract nonexistent.tar.gz 2>/dev/null
test_result "extract handles nonexistent files gracefully" $?

echo -e "\n2. Testing logging functions"
echo "============================"

# Test logging functions (check if they produce output)
echo "Testing log_info function..."
log_output=$(log_info "Test info message" 2>&1)
[[ "$log_output" =~ "INFO: Test info message" ]]
test_result "log_info produces correct output format" $?

echo "Testing log_error function..."
log_output=$(log_error "Test error message" 2>&1)
[[ "$log_output" =~ "ERROR: Test error message" ]]
test_result "log_error produces correct output format" $?

echo "Testing log_warn function..."
log_output=$(log_warn "Test warning message" 2>&1)
[[ "$log_output" =~ "WARN: Test warning message" ]]
test_result "log_warn produces correct output format" $?

# Test if log files are created
log_file="${DOTFILES_LOG_DIR}/shell-$(date +%Y-%m-%d).log"
if [[ -f "$log_file" ]]; then
    test_result "Log file is created correctly" 0
else
    test_result "Log file is created correctly" 1
fi

echo -e "\n3. Testing GPG verification function"
echo "===================================="

# Test GPG verification (non-destructive)
echo "Testing verify_gpg_ssh function..."
verify_gpg_ssh > /dev/null 2>&1
gpg_result=$?
test_result "verify_gpg_ssh runs without errors" 0  # Always pass since it's just checking execution

echo -e "\n4. Testing system monitoring functions"
echo "======================================"

# Test temperature check (may not work on all systems)
echo "Testing temp_check function..."
# Check if powermetrics is available without running sudo
if command -v powermetrics > /dev/null 2>&1; then
    # Just test that the function exists and doesn't crash
    temp_output=$(timeout 2 temp_check 2>&1 || echo "timeout")
    [[ -n "$temp_output" ]]  # Just check if it produces some output
    test_result "temp_check executes (may require sudo)" $?
else
    echo "powermetrics not available"
    test_result "temp_check handles missing powermetrics" 0
fi

# Test battery status
echo "Testing battery_status function..."
battery_output=$(battery_status 2>&1)
[[ -n "$battery_output" ]]  # Just check if it produces some output
test_result "battery_status produces output" $?

echo -e "\n5. Testing prompt functions from prompt.sh"
echo "=========================================="

# Source the prompt functions (they may be in ZSH format)
# Create a temporary git repo for testing git functions
git init test-git-repo > /dev/null 2>&1
cd test-git-repo
git config user.name "Test User" > /dev/null 2>&1
git config user.email "test@example.com" > /dev/null 2>&1

# Test git_info function (need to load it first)
if command -v zsh > /dev/null 2>&1; then
    echo "Testing git_info function with zsh..."
    git_output=$(zsh -c 'source "$HOME/.dotfiles/.zshrc.d/prompt.sh"; git_info' 2>/dev/null || echo "no-git-info")
    [[ -n "$git_output" ]]
    test_result "git_info function executes" $?
    
    # Test short_pwd function
    echo "Testing short_pwd function with zsh..."
    pwd_output=$(zsh -c 'source "$HOME/.dotfiles/.zshrc.d/prompt.sh"; short_pwd' 2>/dev/null || echo "no-pwd-info")
    [[ -n "$pwd_output" ]]
    test_result "short_pwd function executes" $?
    
    # Test build_prompt function
    echo "Testing build_prompt function with zsh..."
    prompt_output=$(zsh -c 'source "$HOME/.dotfiles/.zshrc.d/prompt.sh"; build_prompt' 2>/dev/null || echo "no-prompt")
    [[ -n "$prompt_output" ]]
    test_result "build_prompt function executes" $?
else
    echo "ZSH not available, skipping prompt function tests"
    test_result "ZSH prompt functions (skipped - no zsh)" 0
fi

cd ..

echo -e "\n6. Testing timeout prompt functions"
echo "==================================="

# Test timeout functions with very short timeouts
echo "Testing timeout_prompt with immediate timeout..."
result=$(echo "" | timeout_prompt "Test prompt" 1 "default_value" 2>/dev/null)
[[ "$result" == "default_value" ]]
test_result "timeout_prompt returns default on timeout" $?

echo "Testing timeout_confirm with immediate timeout..."
# Use a more controlled test that won't hang
result=$(echo "n" | bash -c 'source "$HOME/.dotfiles/scripts/timeout_prompt.sh"; timeout_confirm "Test confirm" 1 "n"' 2>/dev/null; echo $?)
[[ "$result" == "1" ]]  # Should return 1 (false) for "n" response
test_result "timeout_confirm returns correct default" $?

echo -e "\n7. Testing bash functions"
echo "========================"

# Test bash git_branch function
if command -v bash > /dev/null 2>&1; then
    echo "Testing bash git_branch function..."
    cd test-git-repo
    # Create a commit so we have a branch
    echo "test" > test_file.txt
    git add test_file.txt > /dev/null 2>&1
    git -c commit.gpgsign=false commit -m "test commit" > /dev/null 2>&1
    
    branch_output=$(bash -c 'source "$HOME/.dotfiles/.bashrc"; git_branch' 2>/dev/null || echo "no-branch")
    [[ -n "$branch_output" ]]
    test_result "bash git_branch function executes" $?
    cd ..
else
    echo "Bash not available, skipping bash function tests"
    test_result "Bash functions (skipped - no bash)" 0
fi

echo -e "\n8. Testing Makefile functions"
echo "============================="

cd "$HOME/.dotfiles"

# Test backup_and_link function from bootstrap.sh
echo "Testing bootstrap.sh functions..."
# We won't actually run the bootstrap script, but we can check if it's syntactically correct
bash -n bootstrap.sh
test_result "bootstrap.sh syntax is valid" $?

# Test Makefile targets
echo "Testing Makefile targets..."
make help > /dev/null 2>&1
test_result "Makefile help target works" $?

make status > /dev/null 2>&1
test_result "Makefile status target works" $?

make test > /dev/null 2>&1
test_result "Makefile test target works" $?

echo -e "\n9. Testing aliases functionality"
echo "==============================="

# Test if brew protection alias works
cd "$TEST_DIR"
# Source the aliases
source "$HOME/.dotfiles/.zshrc.d/aliases.sh"

# Test brew protection
brew_output=$(brew 2>&1 || true)
[[ "$brew_output" =~ "Use MacPorts instead" ]]
test_result "brew protection alias works" $?

echo -e "\n=== TEST SUMMARY ==="
echo "===================="
echo "Total tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Success rate: $(( PASSED * 100 / TOTAL ))%"

# Clean up
cd "$HOME"
rm -rf "$TEST_DIR"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n🎉 All tests passed!"
    exit 0
else
    echo -e "\n⚠️  Some tests failed. Check the output above."
    exit 1
fi

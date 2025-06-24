#!/bin/bash
# Simple timeout-based user prompts with fallback
# Implements system rule for non-blocking interactions
# KISS principle - minimal, readable, reliable

set -e

# Simple timeout prompt
timeout_prompt() {
    local prompt="$1"
    local timeout="${2:-10}"
    local default="${3:-n}"
    local response
    
    echo -n "$prompt (timeout: ${timeout}s, default: $default): " >&2
    
    if read -t "$timeout" response 2>/dev/null; then
        if [[ -n "$response" ]]; then
            echo "$response"
        else
            echo "$default"
        fi
    else
        echo >&2
        echo "Timeout reached, using default: $default" >&2
        echo "$default"
    fi
}

# Simple yes/no confirmation
timeout_confirm() {
    local prompt="$1"
    local timeout="${2:-10}"
    local default="${3:-n}"
    local response
    
    response=$(timeout_prompt "$prompt [y/N]" "$timeout" "$default")
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss]|1|true)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Test function
test_prompts() {
    echo "=== Testing Simple Timeout Prompts ==="
    
    echo "1. Basic prompt (3s timeout):"
    result=$(timeout_prompt "Enter value" 3 "test")
    echo "Got: '$result'"
    
    echo -e "\n2. Confirmation (3s timeout):"
    if timeout_confirm "Proceed" 3 "n"; then
        echo "User confirmed"
    else
        echo "User declined or timed out"
    fi
    
    echo -e "\n3. Quick confirmation (1s timeout):"
    if timeout_confirm "Quick test" 1 "y"; then
        echo "Confirmed (or defaulted to yes)"
    else
        echo "Declined"
    fi
}

# Export functions
export -f timeout_prompt timeout_confirm

# Run test if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "test" ]]; then
        test_prompts
    else
        echo "Usage: $0 [test]"
        echo "Functions: timeout_prompt, timeout_confirm"
    fi
fi

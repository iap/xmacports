#!/bin/bash
# Simple usage example for timeout prompts

source "$(dirname "$0")/../scripts/timeout_prompt.sh"

echo "=== Timeout Prompt Examples ==="

# Example 1: Basic usage with auto-timeout
echo "1. Auto-timeout example (will timeout in 2 seconds):"
result=$(timeout_prompt "Enter something" 2 "auto-default")
echo "Result: $result"

# Example 2: Confirmation with default 'no'
echo -e "\n2. Confirmation example (will timeout to 'no' in 2 seconds):"
if timeout_confirm "Continue with operation" 2 "n"; then
    echo "✅ Operation confirmed"
else
    echo "❌ Operation cancelled"
fi

# Example 3: Confirmation with default 'yes'
echo -e "\n3. Quick confirmation (will timeout to 'yes' in 1 second):"
if timeout_confirm "Apply safe changes" 1 "y"; then
    echo "✅ Changes applied"
else
    echo "❌ Changes skipped"
fi

echo -e "\n✅ Examples completed"

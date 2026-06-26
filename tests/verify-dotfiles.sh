#!/bin/bash
set -eu

source "$HOME/.dotfiles/.config/env.d/platform.sh"

FAILED=0

echo ""
echo "1. Platform Detection Tests"
if is_macos; then
    echo "   - is_macos: PASS (true on macOS)"
else
    echo "   - is_macos: SKIP (false on non-macOS)"
fi
if is_linux; then
    echo "   - is_linux: PASS (true on Linux)"
else
    echo "   - is_linux: PASS (false on non-Linux)"
fi

echo ""
echo "2. False Positive Prevention"

# Test that read-only /opt/local doesn't trigger MacPorts on Linux
if is_linux; then
    echo "   - MacPorts guard: Testing read-only path detection..."
    if [[ -d "/opt/local" ]] && [[ ! -w "/opt/local" ]]; then
      if [[ -z "${MACPORTS_PREFIX:-}" ]] || [[ "$MACPORTS_PREFIX" != "/opt/local" ]]; then
            echo "   - PASS: Read-only /opt/local ignored correctly"
        else
            echo "   - FAIL: Read-only /opt/local incorrectly activated"
            ((FAILED++))
        fi
    else
        echo "   - SKIP: /opt/local writable or missing (not applicable)"
    fi
else
    echo "   - SKIP: macOS platform (MacPorts not guarded by read-only check)"
fi

echo ""
echo "3. PATH Integrity"

PATH_COUNT=$(echo "$PATH" | tr ':' '\n' | sort | uniq -d | wc -l | tr -d ' ')
if [[ "$PATH_COUNT" -eq 0 ]]; then
    echo "   - PASS: No duplicate PATH entries"
else
    echo "   - FAIL: Duplicate PATH entries found: $PATH_COUNT"
    ((FAILED++))
fi

if [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
    echo "   - PASS: User bin in PATH"
else
    echo "   - FAIL: User bin missing from PATH"
    ((FAILED++))
fi

echo ""
echo "4. Required Tool Availability"

for tool in ls grep sed curl; do
    if has_cmd "$tool"; then
        echo "   - PASS: $tool available"
    else
        echo "   - FAIL: $tool missing"
        ((FAILED++))
    fi
done

echo ""
echo "5. XDG Directory Compliance"

for var in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME; do
    if [[ -n "${!var:-}" ]]; then
        echo "   - PASS: $var set to ${!var}"
    else
        echo "   - FAIL: $var not set"
        ((FAILED++))
    fi
done

if [[ $FAILED -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
else
    echo "=== $FAILED TEST(S) FAILED ==="
    exit 1
fi
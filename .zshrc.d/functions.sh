#!/bin/zsh
# Simplified functions - essential utilities with enhanced output

# Basic utility
mkcd() {
  mkdir -p "$1" && cd "$1" || return
}

# Simple logging
log_info() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log_warn() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2
}

# GPG verification function
verify_gpg_ssh() {
    if ! command -v gpg >/dev/null 2>&1; then
        log_warn "GPG not found, SSH authentication may not work"
        return 1
    fi
    
    if [ ! -S "$SSH_AUTH_SOCK" ]; then
        log_warn "GPG agent SSH socket not available"
        return 1
    fi
    
    log_info "GPG-SSH integration verified"
    return 0
}

# System monitoring functions
temp_check() {
    if command -v powermetrics >/dev/null 2>&1; then
        sudo powermetrics --samplers smc_temp -n 1 2>/dev/null | grep -i temp || echo "Temperature monitoring unavailable"
    else
        echo "powermetrics not available"
    fi
}

battery_status() {
    pmset -g batt | grep -v "No estimate"
}

# Enhanced functions with structured output for automation and scripting

# Core context information
context() {
    echo "DIR: $(pwd)"
    echo "FILES: $(ls -1 | wc -l | tr -d ' ')"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d ' ') changes)"
    fi
}

# Simple file display
showfile() {
    local file="$1"
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo "Usage: showfile <filename>"
        return 1
    fi
    echo "FILE: $file ($(stat -f %z "$file" 2>/dev/null || echo '?') bytes)"
    cat "$file"
}

# Find files simply
findfile() {
    find . -name "*$1*" -type f 2>/dev/null | head -10
}

# Git status with structured output
gitstat() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository"
        return 1
    fi
    local root changes
    root="$(git rev-parse --show-toplevel)"
    changes="$(git status --porcelain)"
    echo "REPO: $(basename "$root")"
    echo "BRANCH: $(git branch --show-current)"
    echo "CHANGES: $(echo "$changes" | grep -c . 2>/dev/null || echo 0)"
    [[ -n "$changes" ]] && echo "$changes" | head -5
}

# System environment info
envinfo() {
    echo "OS: $(sw_vers -productVersion)"
    echo "SHELL: $SHELL"
    echo "MACPORTS: $(port version 2>/dev/null | head -1 || echo 'not bootstrapped')"
    echo "GIT: $(git --version 2>/dev/null | cut -d' ' -f3 || echo 'not bootstrapped')"
}

# GPG unlock helper
unlock_gpg() {
    echo "Unlocking GPG key..."
    echo "test" | gpg --clearsign >/dev/null 2>&1 && echo "✅ GPG key unlocked" || echo "❌ Failed to unlock"
}

# Foundry wrappers to scope DYLD_LIBRARY_PATH (macOS/MacPorts)
_with_foundry_libs() {
    if [[ -x "$HOME/.dotfiles/bin/with-foundry-libs" ]]; then
        "$HOME/.dotfiles/bin/with-foundry-libs" "$@"
    else
        "$@"
    fi
}

forge() { _with_foundry_libs command forge "$@"; }
cast() { _with_foundry_libs command cast "$@"; }
anvil() { _with_foundry_libs command anvil "$@"; }

# Privacy and security functions
randomize_mac() {
    local interface="${1:-en0}"
    if [[ $EUID -eq 0 ]]; then
        local new_mac=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
        ifconfig "$interface" ether "$new_mac"
        echo "MAC randomized: $new_mac"
    else
        echo "Requires sudo: sudo randomize_mac"
    fi
}

check_privacy() {
    echo "WiFi MAC: $(ifconfig en0 2>/dev/null | grep ether | awk '{print $2}' || echo 'N/A')"
    echo "Private Address: $(system_profiler SPAirPortDataType 2>/dev/null | grep -q "Private" && echo "Enabled" || echo "Check System Settings")"
    echo "Telemetry Blocking: $(env | grep -c "TELEMETRY\|DO_NOT_TRACK\|ANALYTICS" || echo "0") variables set"
    echo "Network Connections: $(lsof -i | wc -l | tr -d ' ') active"
}

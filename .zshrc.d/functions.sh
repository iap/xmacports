#!/bin/zsh
# Simplified functions - essential utilities with enhanced output

# Basic utility
mkcd() { 
    mkdir -p "$1" && cd "$1" 
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
    echo "USER: $USER"
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
    echo "REPO: $(basename $(git rev-parse --show-toplevel))"
    echo "BRANCH: $(git branch --show-current)"
    echo "CHANGES: $(git status --porcelain | wc -l | tr -d ' ')"
    [[ "$(git status --porcelain | wc -l | tr -d ' ')" -gt 0 ]] && git status --porcelain | head -5
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

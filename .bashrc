#!/bin/bash
# Bash configuration for legacy compatibility
# Optional per system rules but provides fallback

# Source common profile
if [ -f "$HOME/.profile" ]; then
    source "$HOME/.profile"
fi

# Load centralized environment
if [ -f "$HOME/.dotfiles/.config/env.d/default.sh" ]; then
    source "$HOME/.dotfiles/.config/env.d/default.sh"
fi

# Basic bash-specific settings
set -o vi
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=10000
export HISTFILESIZE=10000

# Simple bash prompt (lightweight)
if [[ -t 1 ]]; then
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
    
    # Simple git prompt for bash
    git_branch() {
        git symbolic-ref --short HEAD 2>/dev/null
    }
    
    # Build prompt: ~/path (branch) ❯ 
    PS1='\[${CYAN}\]\w\[${RESET}\]'
    PS1+='\[${BLUE}\]$(branch=$(git_branch); [[ -n $branch ]] && echo " ($branch)")\[${RESET}\]'
    PS1+=' \[${GREEN}\]❯\[${RESET}\] '
    export PS1
fi

# Load local bash customizations
if [ -f "$HOME/.bashrc.local" ]; then
    source "$HOME/.bashrc.local"
fi

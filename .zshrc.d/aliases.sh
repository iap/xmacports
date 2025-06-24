#!/bin/zsh
# Simplified aliases - essential commands with enhanced structured output

# Essential navigation
alias ll='ls -la'
alias ..='cd ..'

# MacPorts essentials
alias install='sudo port install'
alias update='sudo port selfupdate && sudo port upgrade outdated'

# Git essentials
alias gs='git status'
alias ga='git add'
alias gc='git commit'

# Homebrew protection
brew() {
    echo "Use MacPorts instead: port install <package>"
    return 1
}

# Enhanced commands with structured output for better automation and scripting
# Context and status
alias where='echo "DIR: $(basename $(pwd))" && echo "PATH: $(pwd)" && echo "FILES: $(ls -1 | wc -l | tr -d " ")"'
alias status='echo "PWD: $(pwd)" && echo "USER: $USER" && echo "DATE: $(date +"%Y-%m-%d %H:%M:%S")" && if git rev-parse --git-dir >/dev/null 2>&1; then echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d " ") changes)"; fi'

# File operations
alias lsf='ls -1'  # Simple file listing
alias count='ls -1 | wc -l | tr -d " "'  # Count files
alias tree='find . -type d -maxdepth 3 | head -15'

# Git info
alias gitinfo='git branch --show-current 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d " " && echo "changes"'

# System info
alias sysinfo='echo "macOS: $(sw_vers -productVersion)" && echo "Shell: $SHELL" && echo "MacPorts: $(port version 2>/dev/null | head -1 || echo "not bootstrapped")"'

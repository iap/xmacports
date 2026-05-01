#!/bin/bash
# Shared aliases — bash 4+ and zsh compatible

# Essential navigation
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

# Context and status
alias where='echo "DIR: $(basename "$(pwd)")" && echo "PATH: $(pwd)" && echo "FILES: $(ls -1 | wc -l | tr -d " ")"'
alias status='echo "PWD: $(pwd)" && echo "DATE: $(date "+%Y-%m-%d %H:%M:%S")" && git rev-parse --git-dir >/dev/null 2>&1 && echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d " ") changes)" || true'

# File operations
alias lsf='ls -1'
alias count='ls -1 | wc -l | tr -d " "'

tree() {
  if command -v gfind > /dev/null 2>&1; then
    gfind . -type d -maxdepth 3 | head -15
  else
    find . -type d | head -15
  fi
}

# Git info
alias gitinfo='git branch --show-current 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d " " && echo "changes"'

# System info
alias sysinfo='echo "macOS: $(sw_vers -productVersion)" && echo "Shell: $SHELL" && echo "MacPorts: $(port version 2>/dev/null | head -1 || echo "not bootstrapped")"'

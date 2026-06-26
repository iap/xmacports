#!/bin/bash
# Shared aliases

set -u

alias ..='cd ..'

if [ "$(uname -s)" = "Darwin" ]; then
  alias install='sudo port install'
  alias update='sudo port selfupdate && sudo port upgrade outdated'
elif command -v apt-get > /dev/null 2>&1; then
  alias install='sudo apt-get install'
  alias update='sudo apt-get update && sudo apt-get upgrade'
elif command -v dnf > /dev/null 2>&1; then
  alias install='sudo dnf install'
  alias update='sudo dnf upgrade'
elif command -v pacman > /dev/null 2>&1; then
  alias install='sudo pacman -S'
  alias update='sudo pacman -Syu'
fi

alias gs='git status'
alias ga='git add'
alias gc='git commit'

if [ "$(uname -s)" = "Darwin" ]; then
  brew() {
    echo "Use MacPorts instead: port install <package>"
    return 1
  }
fi

alias where='echo "DIR: $(basename "$(pwd)")" && echo "PATH: $(pwd)" && echo "FILES: $(ls -1 | wc -l | tr -d " ")"'
alias status='echo "PWD: $(pwd)" && echo "DATE: $(date "+%Y-%m-%d %H:%M:%S")" && git rev-parse --git-dir >/dev/null 2>&1 && echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d " ") changes)" || true'

alias lsf='ls -1'
alias count='ls -1 | wc -l | tr -d " "'

tree() {
  if command -v tree > /dev/null 2>&1; then
    command tree "$@"
  elif command -v gfind > /dev/null 2>&1; then
    gfind . -type d -maxdepth 3 | head -15
  else
    find . -type d | head -15
  fi
}

alias gitinfo='git branch --show-current 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d " " && echo "changes"'

if [ "$(uname -s)" = "Darwin" ]; then
  alias sysinfo='echo "macOS: $(sw_vers -productVersion)" && echo "Shell: $SHELL" && echo "MacPorts: $(port version 2>/dev/null | head -1 || echo "not bootstrapped")"'
else
  alias sysinfo='echo "OS: $(uname -sr)" && echo "Shell: $SHELL"'
fi

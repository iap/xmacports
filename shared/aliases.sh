#!/bin/bash
# Shared aliases

set -u

alias ..='cd ..'

alias gs='git status'
alias ga='git add'
alias gc='git commit'

alias where='echo "DIR: $(basename "$(pwd)")" && echo "PATH: $(pwd)" && echo "FILES: $(ls -1 | wc -l | tr -d " ")"'
alias status='echo "PWD: $(pwd)" && echo "DATE: $(date "+%Y-%m-%d %H:%M:%S")" && git rev-parse --git-dir >/dev/null 2>&1 && echo "GIT: $(git branch --show-current) ($(git status --porcelain | wc -l | tr -d " ") changes)" || true'

alias lsf='ls -1'
alias count='ls -1 | wc -l | tr -d " "'

# tree wrapper — shadows the tree binary intentionally.
# Use \tree or command tree to invoke the real binary directly.
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

alias sysinfo='echo "OS: $(uname -sr)" && echo "Shell: $SHELL" && echo "User bin: $HOME/bin" && echo "Local bin: $HOME/.local/bin"'

# --- secret hygiene: keep creds out of shell history + safe masking ---
# bash: drop export/secret/token lines from history
if [[ -n "${BASH_VERSION:-}" ]]; then
  HISTIGNORE="${HISTIGNORE:+$HISTIGNORE:}export *:secret *:*TOKEN*:*SECRET*:*API_KEY*"
# zsh: ignore lines starting with space + patterns
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  setopt HIST_IGNORE_SPACE
  HISTORY_IGNORE="${HISTORY_IGNORE:+$HISTORY_IGNORE
}export .*
secret .*
.*TOKEN.*
.*SECRET.*
.*API_KEY.*"
fi

# mask a value for safe display (never reveals the secret)
mask() {
  local v="${1:-}"
  if [ -z "$v" ]; then
    echo "(empty)"
    return
  fi
  local prefix="${v:0:4}"
  local tail="${v: -4}"
  printf '%s****...****%s\n' "$prefix" "$tail"
}

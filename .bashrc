#!/bin/bash

# History
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%s "
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
mkdir -p "$(dirname "$HISTFILE")"
shopt -s histappend

# Shell Options
shopt -s autocd 2>/dev/null
shopt -s globstar 2>/dev/null
shopt -s checkwinsize 2>/dev/null

# Load Unified Platform Configuration
if [[ -f "$HOME/.dotfiles/.config/env.d/platform.sh" ]]; then
    source "$HOME/.dotfiles/.config/env.d/platform.sh"
fi

# Load Shared Functions
for f in functions.sh aliases.sh; do
    [[ -f "$HOME/.dotfiles/shared/$f" ]] && source "$HOME/.dotfiles/shared/$f"
done

# Load Optional Tools
# mise (development tool manager)
if has_cmd mise 2>/dev/null; then eval "$(mise activate bash)" 2>/dev/null || true; fi

# Foundry wrappers
if [[ -f "$HOME/.dotfiles/.config/env.d/foundry.sh" ]]; then
    source "$HOME/.dotfiles/.config/env.d/foundry.sh"
fi

# Prompt
if [[ -t 1 ]]; then
    RED=$'\e[0;31m' GREEN=$'\e[0;32m' YELLOW=$'\e[0;33m' CYAN=$'\e[0;36m' RESET=$'\e[0m'
    
    _git_prompt_cache=""
    _git_prompt_last_pwd=""
    _git_prompt_last_time=0
    
    _git_prompt() {
        local now=$(date +%s)
        local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/shell/git_status_${PWD//\//_}"
        local cache_timeout="${GIT_PROMPT_CACHE_TIMEOUT:-5}"
        if [[ "$PWD" != "$_git_prompt_last_pwd" ]] || [[ $((now - _git_prompt_last_time)) -gt $cache_timeout ]]; then
            _git_prompt_last_pwd="$PWD"
            _git_prompt_last_time=$now
            local branch=$(git symbolic-ref --short HEAD 2>/dev/null) mark=""
            [[ -n "$branch" ]] && { git diff --quiet 2>/dev/null || mark="±"; [[ -z "$mark" ]] && { git diff --cached --quiet 2>/dev/null || mark="+"; }; }
            if [[ -n "$branch" ]]; then
                _git_prompt_cache=" ${YELLOW}(${branch}${mark})${RESET}"
            else
                _git_prompt_cache=""
            fi
            echo "$_git_prompt_cache" > "$cache_file" 2>/dev/null
        fi
        echo "$_git_prompt_cache"
    }
    
    _short_pwd() {
        local p="${PWD/#$HOME/~}"
        [[ ${#p} -gt 25 ]] && echo "...${p: -25}" || echo "$p"
    }
    
    _build_prompt() {
        local exit_code=$?
        local exit_prefix=""
        [[ $exit_code -ne 0 ]] && exit_prefix="${RED}[${exit_code}]${RESET} "
        PS1="${exit_prefix}${CYAN}\$(_short_pwd)${RESET}\$(_git_prompt) ${GREEN}❯${RESET} "
    }
    
    PROMPT_COMMAND="_build_prompt${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"
fi

# Completion
[[ -f /opt/local/etc/profile.d/bash_completion.sh ]] && source /opt/local/etc/profile.d/bash_completion.sh 2>/dev/null || true

# Local Overrides
[[ -f "$HOME/.bashrc.local" ]] && source "$HOME/.bashrc.local"

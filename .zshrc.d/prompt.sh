#!/bin/zsh
# Simple ZSH prompt configuration
# Optimized for MacBook Air 2017 performance

# Color definitions for ZSH prompt
RED='%F{red}'
GREEN='%F{green}'
CYAN='%F{cyan}'
YELLOW='%F{yellow}'
RESET='%f'
# Git info function (clean, no conflicts) with caching
git_info() {
    # Cache git status for performance
    local cache_file="$SHELL_CACHE_DIR/git_status_$$"
    local cache_timeout=5
    
    if [[ -f "$cache_file" && $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt $cache_timeout ]]; then
        cat "$cache_file" 2>/dev/null && return
    fi
    
    git rev-parse --git-dir >/dev/null 2>&1 || return
    
    local branch="$(git branch --show-current 2>/dev/null)"
    [[ -z "$branch" ]] && return
    
    # Check for changes
    local mark=""
    git diff --quiet 2>/dev/null || mark="±"
    [[ -z "$mark" ]] && { git diff --cached --quiet 2>/dev/null || mark="+"; }
    
    local result=" ${YELLOW}(${branch}${mark})${RESET}"
    echo "$result" | tee "$cache_file" 2>/dev/null
}

# Short pwd function
short_pwd() {
    local pwd_length=25
    local current_pwd="${PWD/#$HOME/~}"
    
    if [[ ${#current_pwd} -gt $pwd_length ]]; then
        echo "...${current_pwd: -$pwd_length}"
    else
        echo "$current_pwd"
    fi
}

# Main prompt function
build_prompt() {
    local current_dir="${CYAN}$(short_pwd)${RESET}"
    local git_branch_info="$(git_info)"
    local prompt_char="${GREEN}❯${RESET}"
    
    # Show exit code if last command failed
    local exit_code=""
    if [[ $? -ne 0 ]]; then
        exit_code="${RED}[$?]${RESET} "
    fi
    
    # Simple format: [exit_code] ~/path (git_branch±) ❯ 
    echo "${exit_code}${current_dir}${git_branch_info} ${prompt_char} "
}

# Set the prompt (ZSH only)
if [[ -n "$ZSH_VERSION" ]]; then
    setopt PROMPT_SUBST
    PROMPT='$(build_prompt)'
    
    # Right prompt shows useful context information
    RPROMPT='${CYAN}%D{%H:%M}${RESET}'
    
    # Add a blank line before prompt for better readability in terminal sessions
    precmd() {
        # Only add blank line if the terminal is wide enough and not in a script
        if [[ $COLUMNS -gt 80 && -t 1 ]]; then
            echo
        fi
    }
fi

# Function to show current working environment quickly
work_context() {
    echo "Current working directory: $(pwd)"
    echo "Files in directory: $(ls -1 | wc -l | tr -d ' ')"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Git branch: $(git branch --show-current 2>/dev/null)"
        local changes="$(git status --porcelain | wc -l | tr -d ' ')"
        echo "Git changes: $changes"
    fi
}

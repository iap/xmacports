#!/bin/bash
# Bash configuration with version compatibility
# Requires bash 4.0+ for modern features

# Version check and compatibility
if [[ -n "$BASH_VERSION" ]]; then
    BASH_MAJOR="${BASH_VERSION%%.*}"
    if [[ "$BASH_MAJOR" -lt 4 ]]; then
        echo "Warning: bash $BASH_VERSION is outdated. Consider upgrading to bash 5.x" >&2
        echo "Install with: sudo port install bash" >&2
    fi
fi

# Source common profile
if [ -f "$HOME/.profile" ]; then
    source "$HOME/.profile"
fi

# Bash-specific settings
set -o vi
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%s "
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTFILE="$HOME/.bash_history"

# Modern bash features (4.0+)
if [[ "$BASH_MAJOR" -ge 4 ]]; then
    shopt -s autocd 2>/dev/null          # cd by typing directory name
    shopt -s globstar 2>/dev/null        # ** recursive globbing
    shopt -s checkwinsize 2>/dev/null    # check window size after commands
fi

# Bash completion (if available)
if [[ -f /opt/local/etc/profile.d/bash_completion.sh ]]; then
    source /opt/local/etc/profile.d/bash_completion.sh
fi

# Simple bash prompt (lightweight)
if [[ -t 1 ]]; then
    # Colors (use $'\e' so PS1 renders actual escape bytes, not literal \033)
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[0;33m'
    CYAN=$'\e[0;36m'
    RESET=$'\e[0m'
    
    # Cached git prompt for performance
    __git_ps1_cache=""
    __git_ps1_last_pwd=""
    
    git_prompt() {
        local pwd="$PWD"
        if [[ "$pwd" != "$__git_ps1_last_pwd" ]]; then
            __git_ps1_last_pwd="$pwd"
            local branch
            branch=$(git symbolic-ref --short HEAD 2>/dev/null)
            __git_ps1_cache="${branch:+ ($branch)}"
        fi
        echo "$__git_ps1_cache"
    }
    
    # Build prompt: ~/path (branch) ❯ 
    PS1="\[${CYAN}\]\w\[${RESET}\]"
    PS1+="\[${YELLOW}\]\$(git_prompt)\[${RESET}\]"
    PS1+=" \[${GREEN}\]❯\[${RESET}\] "
    export PS1
fi

# Foundry wrappers (shared with Zsh)
if [ -f "$HOME/.dotfiles/.config/env.d/foundry.sh" ]; then
    . "$HOME/.dotfiles/.config/env.d/foundry.sh"
fi

# Load local bash customizations
if [ -f "$HOME/.bashrc.local" ]; then
    source "$HOME/.bashrc.local"
fi

# Cargo environment (only if not already loaded from .profile)
if [[ -z "$CARGO_HOME" && -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

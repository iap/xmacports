#!/bin/bash
# Centralized environment configuration for development environment
# XDG Base Directory Specification compliance

# XDG Base Directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# MacPorts PATH - essential for package management
# Guard against multiple loads
if [[ -z "$DOTFILES_ENV_LOADED" ]]; then
    export DOTFILES_ENV_LOADED=1
    
    # Use dynamic MacPorts prefix detection with fallback
    if command -v port >/dev/null 2>&1; then
        export MACPORTS_PREFIX="$(command -v port | sed 's|/bin/port||')"
    else
        export MACPORTS_PREFIX="/opt/local"
    fi

    # Clean PATH to avoid duplicates
    PATH_CLEAN="$MACPORTS_PREFIX/libexec/gnubin:$MACPORTS_PREFIX/bin:$MACPORTS_PREFIX/sbin:$HOME/bin:$HOME/.local/bin"
    
    # Add Foundry (Ethereum development toolkit)
    if [[ -d "$HOME/.config/.foundry/bin" ]]; then
        PATH_CLEAN="$PATH_CLEAN:$HOME/.config/.foundry/bin"
    fi
    
    # Add system paths, removing duplicates
    for dir in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
        case ":$PATH_CLEAN:" in
            *":$dir:"*) ;;
            *) PATH_CLEAN="$PATH_CLEAN:$dir" ;;
        esac
    done
    export PATH="$PATH_CLEAN"
    unset PATH_CLEAN
else
    # Ensure MACPORTS_PREFIX is available even when guard prevents reload
    export MACPORTS_PREFIX="${MACPORTS_PREFIX:-/opt/local}"
fi

# Basic environment optimized for development
export EDITOR="vim"
export VISUAL="vim"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Performance optimization for efficient builds
export MAKEFLAGS="-j$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# GPG-SSH integration
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || echo "$HOME/.gnupg/S.gpg-agent.ssh")"
export GPG_TTY="$(tty)"

# MacPorts build environment
export CPPFLAGS="-I$MACPORTS_PREFIX/include"
export LDFLAGS="-L$MACPORTS_PREFIX/lib"

# Logging directory
export DOTFILES_LOG_DIR="$HOME/.logs"

# History configuration
export HISTFILE="${XDG_STATE_HOME}/zsh/history"
export HISTSIZE=10000
export SAVEHIST=10000

# Create required directories (only once per session)
if [[ -z "$DOTFILES_DIRS_CREATED" ]]; then
    export DOTFILES_DIRS_CREATED=1
    mkdir -p "$DOTFILES_LOG_DIR" "$(dirname "$HISTFILE")" "$SHELL_CACHE_DIR" "$HOME/.cache/ssh"
fi

# Minimal setup - no external auto-suggestions
# Testing pushclean alias from gitconfig.local

# Friendly settings
# Make output more structured and readable
# Enhanced grep with color
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Enhanced ls with color (GNU ls from MacPorts)
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Color support for various tools
export CLICOLOR=1
export LSCOLORS="ExGxBxDxCxEgEdxbxgxcxd"
export LS_COLORS="di=1;34:ln=1;36:so=1;31:pi=1;33:ex=1;32:bd=1;34;46:cd=1;34;43:su=1;37;41:sg=1;30;43:tw=1;30;42:ow=1;34;43"

# Tree colors (if installed)
export TREE_COLORS="di=1;34:ln=1;36:so=1;31:pi=1;33:ex=1;32:bd=1;34;46:cd=1;34;43"
export LESS="-R -X -F"
export PAGER="less"

# Secure network tool defaults
alias curl='curl --proto =https --tlsv1.2'
alias wget='wget --secure-protocol=TLSv1_2 --https-only'

# Enhanced prompt and output settings
export COLUMNS=${COLUMNS:-80}
export LINES=${LINES:-24}

# Make command output more verbose and informative
export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWSTASHSTATE=1
export GIT_PS1_SHOWUNTRACKEDFILES=1

# Enhanced find and grep defaults
export FINDOPTS="-type f"

# Disable telemetry for common tools
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export HOMEBREW_NO_ANALYTICS=1
export NEXT_TELEMETRY_DISABLED=1
export DO_NOT_TRACK=1

# Shell session context and cache
export SHELL_CACHE_DIR="$HOME/.cache/shell"

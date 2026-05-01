#!/bin/bash
# Centralized environment configuration for development environment
# XDG Base Directory Specification compliance

# XDG Base Directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Platform detection helpers
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# MacPorts PATH - essential for package management (macOS)
# Guard against multiple loads
if [[ -z "$DOTFILES_ENV_LOADED" ]]; then
    export DOTFILES_ENV_LOADED=1
    
    # Use dynamic MacPorts prefix detection with fallback (macOS only)
    if is_macos; then
        if has_cmd port; then
            export MACPORTS_PREFIX="$(command -v port | sed 's|/bin/port||')"
        else
            export MACPORTS_PREFIX="/opt/local"
        fi
    fi

    # Clean PATH to avoid duplicates
    PATH_CLEAN="$HOME/bin:$HOME/.local/bin"
    if is_macos && [[ -n "$MACPORTS_PREFIX" ]]; then
        PATH_CLEAN="$MACPORTS_PREFIX/libexec/gnubin:$MACPORTS_PREFIX/bin:$MACPORTS_PREFIX/sbin:$PATH_CLEAN"
    fi
    
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
    # Ensure MACPORTS_PREFIX is available even when guard prevents reload (macOS only)
    if is_macos; then
        export MACPORTS_PREFIX="${MACPORTS_PREFIX:-/opt/local}"
    fi
fi

# Basic environment optimized for development
export EDITOR="nano"
export VISUAL="nano"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Performance optimization for efficient builds
_ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
export MAKEFLAGS="-j${_ncpu}"
unset _ncpu

# GPG-SSH integration (cross-platform)
if has_cmd gpgconf; then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || echo "$HOME/.gnupg/S.gpg-agent.ssh")"
    [[ -t 0 ]] && export GPG_TTY="$(tty)" || export GPG_TTY=/dev/tty
    gpgconf --launch gpg-agent 2>/dev/null || true
fi

# MacPorts build environment (macOS)
if is_macos && [[ -n "$MACPORTS_PREFIX" ]]; then
    export CPPFLAGS="-I$MACPORTS_PREFIX/include"
    export LDFLAGS="-L$MACPORTS_PREFIX/lib"
fi

# libusb runtime path for Foundry (MacPorts)
# Avoid global DYLD_LIBRARY_PATH; use per-command wrappers in shell functions.

# Logging directory
export DOTFILES_LOG_DIR="$HOME/.cache/logs"

# Shell session context and cache
export SHELL_CACHE_DIR="$HOME/.cache/shell"

# Create required directories (only once per session)
if [[ -z "$DOTFILES_DIRS_CREATED" ]]; then
    export DOTFILES_DIRS_CREATED=1
    if [[ -n "$DOTFILES_LOG_DIR" ]]; then
        mkdir -p "$DOTFILES_LOG_DIR" && chmod 700 "$DOTFILES_LOG_DIR"
    fi
    if [[ -n "$SHELL_CACHE_DIR" ]]; then
        mkdir -p "$SHELL_CACHE_DIR" && chmod 700 "$SHELL_CACHE_DIR"
    fi
    mkdir -p "$HOME/.cache/ssh" && chmod 700 "$HOME/.cache/ssh"
fi

# Friendly settings
# Make output more structured and readable

# Enhanced ls with color (GNU ls from MacPorts when available; BSD fallback)
if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
else
    alias ls='ls -G'
    alias ll='ls -alFG'
    alias la='ls -AG'
    alias l='ls -CFG'
fi

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

# Security hardening
umask 077  # Files: 600, Dirs: 700

# Disable telemetry for common tools
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export HOMEBREW_NO_ANALYTICS=1
export NEXT_TELEMETRY_DISABLED=1
export DO_NOT_TRACK=1

# Additional privacy protection
export DISABLE_TELEMETRY=1
export NO_UPDATE_NOTIFIER=1
export ADBLOCK=1

# grep color compatibility (GNU/BSD)
if grep --color=auto "" /dev/null >/dev/null 2>&1; then
    alias grep='grep --color=auto'
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
else
    alias grep='grep --color=auto'
fi

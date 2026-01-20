#!/bin/bash
# Centralized environment configuration for development environment
# XDG Base Directory Specification compliance

# XDG Base Directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# MacPorts PATH - essential for package management
# Use dynamic MacPorts prefix detection with fallback
if command -v port >/dev/null 2>&1; then
    MACPORTS_PREFIX="$(command -v port | sed 's|/bin/port||')"
else
    MACPORTS_PREFIX="/opt/local"
fi
export PATH="$MACPORTS_PREFIX/libexec/gnubin:$MACPORTS_PREFIX/bin:$MACPORTS_PREFIX/sbin:$HOME/bin:$HOME/.local/bin:$PATH"

# Basic environment optimized for development
export EDITOR="vim"
export VISUAL="vim"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Performance optimization for efficient builds
export MAKEFLAGS="-j$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# GPG-SSH integration
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || echo "$HOME/.gnupg/S.gpg-agent.ssh")"
export GPG_TTY="$(tty 2>/dev/null || echo "$TTY")"

# MacPorts build environment
export CPPFLAGS="-I$MACPORTS_PREFIX/include"
export LDFLAGS="-L$MACPORTS_PREFIX/lib"

# Logging directory
export DOTFILES_LOG_DIR="$HOME/.logs"
mkdir -p "$DOTFILES_LOG_DIR"

# History configuration
export HISTFILE="${XDG_STATE_HOME}/zsh/history"
export HISTSIZE=10000
export SAVEHIST=10000
[[ ! -d "$(dirname "$HISTFILE")" ]] && mkdir -p "$(dirname "$HISTFILE")"

# Minimal setup - no external auto-suggestions
# Testing pushclean alias from gitconfig.local

# Friendly settings
# Make output more structured and readable
export GREP_OPTIONS="--color=auto"
export LESS="-R -X -F"
export PAGER="less"

# Enhanced prompt and output settings
export COLUMNS=${COLUMNS:-80}
export LINES=${LINES:-24}

# Make command output more verbose and informative
export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWSTASHSTATE=1
export GIT_PS1_SHOWUNTRACKEDFILES=1

# Enhanced find and grep defaults
export FINDOPTS="-type f"

# Shell session context and cache
export SHELL_CACHE_DIR="$HOME/.cache/shell"
mkdir -p "$SHELL_CACHE_DIR"
mkdir -p "$HOME/.cache/ssh"

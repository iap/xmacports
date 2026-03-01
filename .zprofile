#!/bin/zsh
# ZSH Profile - Login shell initialization
# Single entry point for all shell configurations per system rules

# Load shared profile configuration
if [[ -f "$HOME/.profile" ]]; then
    source "$HOME/.profile"
fi

# Initialize logging (only if DOTFILES_LOG_DIR is set and not empty)
if [[ -n "$DOTFILES_LOG_DIR" && "$DOTFILES_LOG_DIR" != "" ]]; then
    mkdir -p "$DOTFILES_LOG_DIR" && chmod 700 "$DOTFILES_LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Login shell initialized" >> "$DOTFILES_LOG_DIR/shell-$(date +%Y-%m-%d).log"
    chmod 600 "$DOTFILES_LOG_DIR/shell-$(date +%Y-%m-%d).log" 2>/dev/null
fi

# Note: GPG agent and SSH socket are initialized in centralized environment config

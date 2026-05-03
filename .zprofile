#!/bin/zsh
# ZSH Profile - Login shell initialization
# Single entry point for all shell configurations per system rules

# Load shared profile configuration
if [[ -f "$HOME/.profile" ]]; then
    source "$HOME/.profile"
fi

# Initialize logging only when the directory is writable.
if [[ -n "${DOTFILES_LOG_DIR:-}" ]]; then
    if mkdir -p "$DOTFILES_LOG_DIR" 2>/dev/null && [[ -w "$DOTFILES_LOG_DIR" ]]; then
        chmod 700 "$DOTFILES_LOG_DIR" 2>/dev/null || true
        local log_file="$DOTFILES_LOG_DIR/shell-$(date +%Y-%m-%d).log"
        if : >> "$log_file" 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') Login shell initialized" >> "$log_file"
            chmod 600 "$log_file" 2>/dev/null || true
        fi
    fi
fi

# Note: GPG agent and SSH socket are initialized in centralized environment config

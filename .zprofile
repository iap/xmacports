#!/bin/zsh
# ZSH Profile

if [[ -f "$HOME/.profile" ]]; then
    source "$HOME/.profile"
fi

# Initialize logging only when the directory is writable.
if [[ -n "${DOTFILES_LOG_DIR:-}" ]]; then
    if mkdir -p "$DOTFILES_LOG_DIR" 2>/dev/null && [[ -w "$DOTFILES_LOG_DIR" ]]; then
        chmod 700 "$DOTFILES_LOG_DIR" 2>/dev/null || true
        log_file="$DOTFILES_LOG_DIR/shell-$(date +%Y-%m-%d).log"
        if : >> "$log_file" 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') Login shell initialized" >> "$log_file"
            chmod 600 "$log_file" 2>/dev/null || true
        fi
    fi
fi

# GPG agent and SSH socket are initialized in centralized environment config

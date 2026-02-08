#!/bin/zsh
# ZSH Profile - Login shell initialization
# Single entry point for all shell configurations per system rules

# Load environment configuration first (only if not already loaded)
if [[ -z "$DOTFILES_ENV_LOADED" && -f "$HOME/.dotfiles/.config/env.d/default.sh" ]]; then
    source "$HOME/.dotfiles/.config/env.d/default.sh"
fi

# Initialize logging
if [[ -n "$DOTFILES_LOG_DIR" ]]; then
    mkdir -p "$DOTFILES_LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Login shell initialized" >> "$DOTFILES_LOG_DIR/shell-$(date +%Y-%m-%d).log"
fi

# GPG agent startup with SSH support
if command -v gpgconf >/dev/null 2>&1; then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || echo "$HOME/.gnupg/S.gpg-agent.ssh")"
    export GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"
    
    # Start gpg-agent if not running
    if ! pgrep -x gpg-agent >/dev/null 2>&1; then
        gpg-agent --daemon --enable-ssh-support --write-env-file "$HOME/.gpg-agent-info" >/dev/null 2>&1 || true
    fi
fi

# Note: MacPorts PATH is handled by centralized environment configuration
# The MacPorts installer addition below is redundant and should be removed


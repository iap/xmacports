#!/bin/zsh
# Modular ZSH configuration for MacBook Air 2017
# Uses centralized environment and modular configuration system

# Load environment configuration first
if [[ -f "$HOME/.dotfiles/.zshrc.d/env.sh" ]]; then
    source "$HOME/.dotfiles/.zshrc.d/env.sh"
fi

# Load modular configuration files
for config_file in "$HOME/.dotfiles/.zshrc.d/"*.sh; do
    # Skip env.sh as it's already loaded above
    [[ "$(basename "$config_file")" == "env.sh" ]] && continue
    [[ -f "$config_file" ]] && source "$config_file"
done

# ZSH-specific options for optimal performance
setopt AUTO_CD              # Change directory without 'cd'
setopt EXTENDED_GLOB        # Extended globbing patterns
setopt GLOB_DOTS            # Include dotfiles in glob patterns
setopt HIST_EXPIRE_DUPS_FIRST  # Expire duplicate entries first
setopt HIST_IGNORE_DUPS     # Don't record duplicate entries
setopt HIST_IGNORE_SPACE    # Don't record entries starting with space
setopt HIST_REDUCE_BLANKS   # Remove superfluous blanks
setopt HIST_SAVE_NO_DUPS    # Don't write duplicate entries
setopt HIST_VERIFY          # Show command with history expansion before running
setopt INC_APPEND_HISTORY   # Write history incrementally
setopt SHARE_HISTORY        # Share history between sessions
setopt CORRECT              # Spell correction for commands
setopt COMPLETE_IN_WORD     # Complete from both ends of word
setopt ALWAYS_TO_END        # Move cursor to end after completion

# Color support for ZSH
setopt PROMPT_SUBST         # Enable prompt substitution
autoload -U colors && colors  # Load color support

# Disable unwanted features for performance
unsetopt BEEP               # No beeping
unsetopt FLOW_CONTROL       # Disable start/stop characters

# Load completion system (simplified for reliability)
autoload -Uz compinit
compinit -C

# Basic completion styling
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive matching

# Load local customizations if they exist
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Initialize GPG verification on startup (non-blocking)
if [[ -n "$DOTFILES_LOG_DIR" ]] && declare -f verify_gpg_ssh >/dev/null; then
    verify_gpg_ssh > "$DOTFILES_LOG_DIR/gpg-verify.log" 2>&1 &
    disown
fi

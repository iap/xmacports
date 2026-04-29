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

# ZSH history file (ZSH-only; kept here, not in shared default.sh)
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
[[ -d "$(dirname "$HISTFILE")" ]] || { mkdir -p "$(dirname "$HISTFILE")" && chmod 700 "$(dirname "$HISTFILE")"; }

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
setopt EXTENDED_HISTORY     # Store timestamps for time-based pruning
setopt CORRECT              # Spell correction for commands
setopt COMPLETE_IN_WORD     # Complete from both ends of word
setopt ALWAYS_TO_END        # Move cursor to end after completion

# Color support for ZSH
setopt PROMPT_SUBST         # Enable prompt substitution

# Disable unwanted features for performance
unsetopt BEEP               # No beeping
unsetopt FLOW_CONTROL       # Disable start/stop characters

# Load completion system
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}"
compinit -C -d "$_zcompdump"
unset _zcompdump

# Basic completion styling
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive matching

# Load local customizations if they exist
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Initialize GPG verification on startup (non-blocking) only when log dir is writable.
if [[ -n "${DOTFILES_LOG_DIR:-}" ]] && declare -f verify_gpg_ssh >/dev/null; then
    if mkdir -p "$DOTFILES_LOG_DIR" 2>/dev/null && [[ -w "$DOTFILES_LOG_DIR" ]]; then
        verify_gpg_ssh > "$DOTFILES_LOG_DIR/gpg-verify.log" 2>&1 &
        disown
    fi
fi

# BEGIN SCARB COMPLETIONS
if command -v scarb >/dev/null 2>&1; then
    _scarb_cache="${XDG_CACHE_HOME:-$HOME/.cache}/shell/scarb-completions.zsh"
    _scarb_bin="$(command -v scarb)"
    _scarb_bin_mtime="$(stat -c %Y "$_scarb_bin" 2>/dev/null || /usr/bin/stat -f %m "$_scarb_bin" 2>/dev/null || echo 0)"
    _scarb_cache_mtime="$(stat -c %Y "$_scarb_cache" 2>/dev/null || /usr/bin/stat -f %m "$_scarb_cache" 2>/dev/null || echo 0)"
    if [[ ! -f "$_scarb_cache" || "$_scarb_bin_mtime" -gt "$_scarb_cache_mtime" ]]; then
        scarb completions zsh 2>/dev/null >| "$_scarb_cache"
    fi
    source "$_scarb_cache" 2>/dev/null
    unset _scarb_cache _scarb_bin _scarb_bin_mtime _scarb_cache_mtime
fi
# END SCARB COMPLETIONS

#!/bin/zsh
# ZSH Profile

if [[ -f "$HOME/.profile" ]]; then
  source "$HOME/.profile"
fi

# Load zsh-specific interactive config after shared defaults.
# IMPORTANT: only for NON-interactive login shells. zsh sources .zshrc itself
# for every interactive shell, so sourcing it here unconditionally makes a
# login+interactive shell (the normal Terminal.app case) run the whole
# interactive init TWICE — double PATH building, double `mise activate`,
# double compinit, double prompt wiring.
if [[ ! -o interactive ]] && [[ -f "$HOME/.zshrc" ]]; then
  source "$HOME/.zshrc"
fi

# Initialize logging only when the directory is writable. platform.sh (the
# usual exporter of DOTFILES_LOG_DIR) has not loaded yet at .zprofile time —
# it loads later via .zshrc — so fall back to the same XDG default here.
_log_dir="${DOTFILES_LOG_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/logs}"
if mkdir -p "$_log_dir" 2> /dev/null && [[ -w "$_log_dir" ]]; then
  chmod 700 "$_log_dir" 2> /dev/null || true
  log_file="$_log_dir/shell-$(date +%Y-%m-%d).log"
  if : >> "$log_file" 2> /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Login shell initialized" >> "$log_file"
    chmod 600 "$log_file" 2> /dev/null || true
  fi
fi
unset _log_dir log_file

# GPG agent and SSH socket are initialized in centralized environment config

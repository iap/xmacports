#!/bin/zsh
# ZSH interactive shell configuration
# Sources shared cross-shell config, then ZSH-only extras

# Load ZSH-specific environment (sources default.sh via env.sh)
if [[ -f "$HOME/.dotfiles/.zshrc.d/env.sh" ]]; then
    source "$HOME/.dotfiles/.zshrc.d/env.sh"
fi

# Load shared functions and aliases (bash + zsh compatible)
for _config_file in "$HOME/.dotfiles/shared/"*.sh; do
    [[ -f "$_config_file" ]] && source "$_config_file"
done
unset _config_file

# Load ZSH-only config (prompt, etc.) — skip env.sh already loaded above
for _config_file in "$HOME/.dotfiles/.zshrc.d/"*.sh; do
    [[ "$(basename "$_config_file")" == "env.sh" ]] && continue
    [[ -f "$_config_file" ]] && source "$_config_file"
done
unset _config_file

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
[[ -d "$(dirname "$HISTFILE")" ]] || { mkdir -p "$(dirname "$HISTFILE")" && chmod 700 "$(dirname "$HISTFILE")"; }

# ── ZSH options ───────────────────────────────────────────────────────────────
setopt AUTO_CD
setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt CORRECT
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt PROMPT_SUBST
unsetopt BEEP
unsetopt FLOW_CONTROL

# ── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}"
compinit -C -d "$_zcompdump"
unset _zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ── Scarb completions ─────────────────────────────────────────────────────────
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

# ── GPG verification (non-blocking) ──────────────────────────────────────────
if [[ -n "${DOTFILES_LOG_DIR:-}" ]] && declare -f verify_gpg_ssh >/dev/null; then
    if mkdir -p "$DOTFILES_LOG_DIR" 2>/dev/null && [[ -w "$DOTFILES_LOG_DIR" ]]; then
        verify_gpg_ssh >"$DOTFILES_LOG_DIR/gpg-verify.log" 2>&1 &
        disown
    fi
fi

# ── Local overrides ───────────────────────────────────────────────────────────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

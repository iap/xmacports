#!/bin/bash
# Bash interactive shell configuration — primary shell
# Requires bash 4.0+ (install via: sudo port install bash)

# Warn on outdated system bash (macOS ships 3.2)
if [[ -n "$BASH_VERSION" ]]; then
    _bash_major="${BASH_VERSION%%.*}"
    if [[ "$_bash_major" -lt 4 ]]; then
        echo "Warning: bash $BASH_VERSION is outdated. Install bash 5: sudo port install bash" >&2
    fi
    unset _bash_major
fi

# Source shared profile (env, PATH, XDG, GPG, etc.)
if [ -f "$HOME/.profile" ]; then
    source "$HOME/.profile"
fi

# ── History ──────────────────────────────────────────────────────────────────
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%s "
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTFILE="$HOME/.bash_history"
shopt -s histappend

# ── Shell options (bash 4+) ───────────────────────────────────────────────────
shopt -s autocd 2>/dev/null
shopt -s globstar 2>/dev/null
shopt -s checkwinsize 2>/dev/null
shopt -s cdspell 2>/dev/null

# ── Shared functions and aliases ──────────────────────────────────────────────
if [ -f "$HOME/.dotfiles/shared/functions.sh" ]; then
    source "$HOME/.dotfiles/shared/functions.sh"
fi
if [ -f "$HOME/.dotfiles/shared/aliases.sh" ]; then
    source "$HOME/.dotfiles/shared/aliases.sh"
fi

# ── Foundry wrappers ─────────────────────────────────────────────────────────
if [ -f "$HOME/.dotfiles/.config/env.d/foundry.sh" ]; then
    source "$HOME/.dotfiles/.config/env.d/foundry.sh"
fi

# ── Prompt ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[0;33m'
    CYAN=$'\e[0;36m'
    RESET=$'\e[0m'

    # Git info with per-directory cache (5s TTL), same logic as ZSH prompt
    _git_prompt_cache=""
    _git_prompt_last_pwd=""
    _git_prompt_last_time=0

    _git_prompt() {
        local now
        now=$(date +%s)
        if [[ "$PWD" != "$_git_prompt_last_pwd" || $((now - _git_prompt_last_time)) -gt 5 ]]; then
            _git_prompt_last_pwd="$PWD"
            _git_prompt_last_time=$now
            local branch mark=""
            branch=$(git symbolic-ref --short HEAD 2>/dev/null)
            if [[ -n "$branch" ]]; then
                git diff --quiet 2>/dev/null || mark="±"
                [[ -z "$mark" ]] && { git diff --cached --quiet 2>/dev/null || mark="+"; }
                _git_prompt_cache=" ${YELLOW}(${branch}${mark})${RESET}"
            else
                _git_prompt_cache=""
            fi
        fi
        echo "$_git_prompt_cache"
    }

    # Short pwd: replace $HOME with ~, truncate if > 25 chars
    _short_pwd() {
        local p="${PWD/#$HOME/\~}"
        if [[ ${#p} -gt 25 ]]; then
            echo "...${p: -25}"
        else
            echo "$p"
        fi
    }

    # Build PS1 dynamically via PROMPT_COMMAND to capture $?
    _build_prompt() {
        local last_exit=$?
        local exit_prefix=""
        [[ $last_exit -ne 0 ]] && exit_prefix="${RED}[${last_exit}]${RESET} "
        PS1="${exit_prefix}${CYAN}\$(_short_pwd)${RESET}\$(_git_prompt) ${GREEN}❯${RESET} "
    }

    PROMPT_COMMAND="_build_prompt"
fi

# ── Completion ────────────────────────────────────────────────────────────────
if [[ -f /opt/local/etc/profile.d/bash_completion.sh ]]; then
    source /opt/local/etc/profile.d/bash_completion.sh
elif [[ -f /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
fi

# Scarb completions (Starknet/Cairo toolchain)
if command -v scarb >/dev/null 2>&1; then
    _scarb_cache="${XDG_CACHE_HOME:-$HOME/.cache}/shell/scarb-completions.bash"
    _scarb_bin="$(command -v scarb)"
    _scarb_bin_mtime=$(stat -c %Y "$_scarb_bin" 2>/dev/null || stat -f %m "$_scarb_bin" 2>/dev/null || echo 0)
    _scarb_cache_mtime=$(stat -c %Y "$_scarb_cache" 2>/dev/null || stat -f %m "$_scarb_cache" 2>/dev/null || echo 0)
    if [[ ! -f "$_scarb_cache" || "$_scarb_bin_mtime" -gt "$_scarb_cache_mtime" ]]; then
        scarb completions bash 2>/dev/null >"$_scarb_cache"
    fi
    # shellcheck source=/dev/null
    source "$_scarb_cache" 2>/dev/null
    unset _scarb_cache _scarb_bin _scarb_bin_mtime _scarb_cache_mtime
fi

# ── Local overrides ───────────────────────────────────────────────────────────
if [ -f "$HOME/.bashrc.local" ]; then
    source "$HOME/.bashrc.local"
fi

# Cargo (only if not already loaded from .profile)
if [[ -z "$CARGO_HOME" && -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

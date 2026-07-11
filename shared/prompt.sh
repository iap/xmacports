#!/bin/bash
# Unified shell prompt — shared logic, per-shell renderers.
# Sources from .zshrc.d/prompt.sh (zsh) and .bashrc (bash).
# Color is applied in the renderer so the core stays shell-agnostic.

set -u

if [[ -n "${DOTFILES_PROMPT_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_PROMPT_LOADED=1

# --- shared, color-free core ---

short_pwd() {
  local pwd_length=25
  local current_pwd="${PWD/#$HOME/~}"
  if [[ ${#current_pwd} -gt $pwd_length ]]; then
    echo "...${current_pwd: -$pwd_length}"
  else
    echo "$current_pwd"
  fi
}

# Git branch + change marker, cached per-directory for GIT_PROMPT_CACHE_TIMEOUT sec.
# Output: " (branch±)" on success, "" when not in a repo.
git_prompt_info() {
  local dir_hash="${PWD//\//_}"
  local cache_file="${SHELL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/shell/git_status_${dir_hash}}"
  local cache_timeout="${GIT_PROMPT_CACHE_TIMEOUT:-5}"

  local cache_mtime=0
  if [[ -f "$cache_file" ]]; then
    cache_mtime=$(/usr/bin/stat -f %m "$cache_file" 2> /dev/null || stat -c %Y "$cache_file" 2> /dev/null || echo 0)
  fi
  if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - cache_mtime)) -lt $cache_timeout ]]; then
    cat "$cache_file" 2> /dev/null && return
  fi

  git rev-parse --git-dir > /dev/null 2>&1 || {
    rm -f "$cache_file"
    return
  }

  local branch
  branch=$(git branch --show-current 2> /dev/null)
  [[ -z "$branch" ]] && return

  local mark=""
  git diff --quiet 2> /dev/null || mark="±"
  [[ -z "$mark" ]] && { git diff --cached --quiet 2> /dev/null || mark="+"; }

  local result=" (${branch}${mark})"
  echo "$result" > "$cache_file" 2> /dev/null
  echo "$result"
}

# --- per-shell renderers ---

_prompt_render_zsh() {
  local last_exit="$1"
  local exit_prefix=""
  [[ $last_exit -ne 0 ]] && exit_prefix="%F{red}[${last_exit}]%f "
  echo "${exit_prefix}%F{cyan}$(short_pwd)%f$(git_prompt_info) %F{green}❯%f "
}

_prompt_render_bash() {
  local exit_code=$?
  local RED=$'\e[0;31m' GREEN=$'\e[0;32m' CYAN=$'\e[0;36m' RESET=$'\e[0m'
  local exit_prefix=""
  [[ $exit_code -ne 0 ]] && exit_prefix="${RED}[${exit_code}]${RESET} "
  PS1="${exit_prefix}${CYAN}$(short_pwd)${RESET}$(git_prompt_info) ${GREEN}❯${RESET} "
}

# --- wire it up per shell ---

if [[ -n "${ZSH_VERSION:-}" ]]; then
  autoload -Uz colors 2> /dev/null && colors
  PROMPT='$(_prompt_render_zsh $_prompt_last_exit)'
  RPROMPT='%F{cyan}%D{%H:%M}%f'
  precmd() {
    _prompt_last_exit=$?
    [[ $COLUMNS -gt 80 && -t 1 ]] && echo
  }
  _prompt_last_exit=0
elif [[ -n "${BASH_VERSION:-}" ]]; then
  if [[ -t 1 ]]; then
    PROMPT_COMMAND="_prompt_render_bash${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"
  fi
fi

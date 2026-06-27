#!/bin/zsh
# ZSH prompt configuration

RED='%F{red}'
GREEN='%F{green}'
CYAN='%F{cyan}'
YELLOW='%F{yellow}'
RESET='%f'
git_info() {
  local dir_hash="${PWD//\//_}"
  local cache_file="${SHELL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/shell/git_status_${dir_hash}}"
  local cache_timeout="${GIT_PROMPT_CACHE_TIMEOUT:-5}"

  if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(/usr/bin/stat -f %m "$cache_file" 2> /dev/null || stat -c %Y "$cache_file" 2> /dev/null || echo 0))) -lt $cache_timeout ]]; then
    cat "$cache_file" 2> /dev/null && return
  fi

  git rev-parse --git-dir > /dev/null 2>&1 || {
    rm -f "$cache_file"
    return
  }

  local branch="$(git branch --show-current 2> /dev/null)"
  [[ -z "$branch" ]] && return

  # Check for changes
  local mark=""
  git diff --quiet 2> /dev/null || mark="±"
  [[ -z "$mark" ]] && { git diff --cached --quiet 2> /dev/null || mark="+"; }

  local result=" ${YELLOW}(${branch}${mark})${RESET}"
  echo "$result" > "$cache_file" 2> /dev/null
  echo "$result"
}

# Short pwd
short_pwd() {
  local pwd_length=25
  local current_pwd="${PWD/#$HOME/~}"

  if [[ ${#current_pwd} -gt $pwd_length ]]; then
    echo "...${current_pwd: -$pwd_length}"
  else
    echo "$current_pwd"
  fi
}

# Main prompt function
build_prompt() {
  local last_exit="$1"
  local current_dir="${CYAN}$(short_pwd)${RESET}"
  local git_branch_info="$(git_info)"
  local prompt_char="${GREEN}❯${RESET}"

  # Show exit code if last command failed
  local exit_prefix=""
  if [[ $last_exit -ne 0 ]]; then
    exit_prefix="${RED}[${last_exit}]${RESET} "
  fi

  echo "${exit_prefix}${current_dir}${git_branch_info} ${prompt_char} "
}

if [[ -n "$ZSH_VERSION" ]]; then
  PROMPT='$(build_prompt $_prompt_last_exit)'

  RPROMPT='${CYAN}%D{%H:%M}${RESET}'

  precmd() {
    _prompt_last_exit=$?
    # Only add blank line if the terminal is wide enough and not in a script
    if [[ $COLUMNS -gt 80 && -t 1 ]]; then
      echo
    fi
  }
fi

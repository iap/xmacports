#!/bin/bash
# Unified platform detection and environment setup — single source of truth.
# Sourced by bash (.bashrc -> functions.sh) and zsh (.zshrc shared/*.sh loop).
# Keep all logic POSIX/portable: no bash-only word-splitting (zsh does not
# split unquoted $var), so PATH helpers work identically in both shells.
# Replaces the legacy .config/env.d/platform.sh wrapper.

set -u

# Load guard — use non-exported var to avoid leaking to child processes
if [[ -n "${DOTFILES_PLATFORM_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_PLATFORM_LOADED=1

# --- Platform detection ---
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" > /dev/null 2>&1; }

# DOTFILES_ROOT defaults to ~/.dotfiles if not already set
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# --- XDG Base Directories ---
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# --- Editor & Locale ---
export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-$EDITOR}"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# --- MAKE_JOBS (parallel builds) ---
MAKE_JOBS=""
if has_cmd nproc; then
  MAKE_JOBS=$(nproc 2> /dev/null || echo 2)
elif [[ -f /proc/cpuinfo ]]; then
  MAKE_JOBS=$(grep -c ^processor /proc/cpuinfo 2> /dev/null || echo 2)
else
  MAKE_JOBS=2
fi
export MAKEFLAGS="-j$MAKE_JOBS"

# --- Foundry (Ethereum) - optional ---
export FOUNDRY_BIN_PATH="${FOUNDRY_BIN_PATH:-}"
if [[ -z "$FOUNDRY_BIN_PATH" ]]; then
  for p in "$HOME/.foundry/bin" "$HOME/.config/.foundry/bin"; do
    if [[ -d "$p" && -r "$p" ]]; then
      export FOUNDRY_BIN_PATH="$p"
      break
    fi
  done
fi

# --- GPG agent SSH socket ---
if has_cmd gpgconf; then
  _gpg_ssh_socket=$(gpgconf --list-dirs agent-ssh-socket 2> /dev/null)
  if [[ -n "$_gpg_ssh_socket" ]] && [[ -S "$_gpg_ssh_socket" ]]; then
    export SSH_AUTH_SOCK="$_gpg_ssh_socket"
  fi
  unset _gpg_ssh_socket
fi

# --- GPG_TTY ---
if [[ -t 0 ]]; then
  GPG_TTY_VALUE=$(tty 2> /dev/null || echo /dev/tty)
  export GPG_TTY="$GPG_TTY_VALUE"
else
  export GPG_TTY=/dev/tty
fi

# --- Safe mkdir helper ---
safe_mkdir() {
  mkdir -p "$1" 2> /dev/null
  chmod 700 "$1" 2> /dev/null || true
}
safe_mkdir "$XDG_CACHE_HOME/logs"
safe_mkdir "$XDG_CACHE_HOME/ssh"
safe_mkdir "$XDG_CACHE_HOME/shell"
safe_mkdir "$XDG_STATE_HOME/shell"

# --- ls colors (GNU vs BSD) ---
if ls --color=auto > /dev/null 2>&1; then
  alias ls='ls --color=auto'
  alias ll='ls -alF --color=auto'
  alias la='ls -A --color=auto'
fi

# --- grep colors (GNU) ---
if grep --color=auto "" /dev/null > /dev/null 2>&1; then
  alias grep='grep --color=auto'
fi

# --- Privacy / telemetry opt-out ---
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export HOMEBREW_NO_ANALYTICS=1
export NEXT_TELEMETRY_DISABLED=1
export DO_NOT_TRACK=1
export DISABLE_TELEMETRY=1
export NO_UPDATE_NOTIFIER=1

# --- Path utilities ---
# Portable PATH dedupe — uses only POSIX parameter expansion (no unquoted
# word-splitting), so it works in bash, zsh, and dash. The naive
# `for seg in $PATH` form silently fails under zsh (no word-split), leaving
# duplicates untouched.
path_dedupe() {
  [ -z "${PATH:-}" ] && return 0
  local normalized="" segment remaining="$PATH"
  while [ -n "$remaining" ]; do
    segment="${remaining%%:*}"
    case "$remaining" in
      *:*) remaining="${remaining#*:}" ;;
      *) remaining="" ;;
    esac
    [ -n "$segment" ] || continue
    case ":$normalized:" in
      *":$segment:"*) ;;
      *) normalized="${normalized:+$normalized:}$segment" ;;
    esac
  done
  PATH="$normalized"
}

path_prepend_if_present() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  [[ -d "$dir" ]] || return 0
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
  esac
  PATH="$dir${PATH:+:$PATH}"
}

# --- Build PATH ---
# System dirs first (prepended LAST so they appear FIRST in final PATH)
for dir in \
  "/sbin" \
  "/usr/sbin" \
  "/bin" \
  "/usr/bin" \
  "/usr/local/sbin" \
  "/usr/local/bin" \
  "/opt/local/bin" \
  "${FOUNDRY_BIN_PATH:-}" \
  "$HOME/.local/bin" \
  "$HOME/bin"; do
  path_prepend_if_present "$dir"
done

# mise shims LAST so they appear FIRST (highest priority)
path_prepend_if_present "$HOME/.local/share/mise/shims"

path_dedupe
export PATH

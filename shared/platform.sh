#!/bin/bash
# Unified platform detection and environment setup — single source of truth.
# Sources from .profile (login), .bashrc/.zshrc (interactive), and scripts.
# Replaces: .config/env.d/platform.sh

# NOTE: no top-level `set -u` — this file is *sourced* into interactive shells,
# so shell options set here leak into the user's session (see shared/README rule).
# All variable reads below use ${VAR:-} defaults and are safe under a caller's `set -u`.

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
elif command -v sysctl > /dev/null 2>&1; then
  MAKE_JOBS=$(sysctl -n hw.ncpu 2> /dev/null || echo 2)
else
  MAKE_JOBS=2
fi
# Never clobber a user-supplied MAKEFLAGS.
if [[ -z "${MAKEFLAGS:-}" ]]; then
  export MAKEFLAGS="-j$MAKE_JOBS"
fi

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
# Only set GPG_TTY when stdin is a real TTY. In non-interactive
# (headless/CI) sessions, leave it UNSET: a dummy like /dev/tty
# makes pinentry try to open a device that doesn't exist and fail with
# "Device not configured". GnuPG falls back correctly when it is unset.
if [[ -t 0 ]]; then
  GPG_TTY_VALUE=$(tty 2> /dev/null || true)
  if [[ -n "$GPG_TTY_VALUE" ]]; then
    export GPG_TTY="$GPG_TTY_VALUE"
  else
    unset GPG_TTY
  fi
else
  unset GPG_TTY
fi

# --- Safe mkdir helper ---
safe_mkdir() {
  mkdir -p "$1" 2> /dev/null
  chmod 700 "$1" 2> /dev/null || true
}
# Log dir for shell-init diagnostics (login-shell log, background GPG verify).
# Exported so call sites (.zprofile, .zshrc) do not each hardcode the path;
# .zprofile runs before this file loads and falls back to the same default.
export DOTFILES_LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/logs"
safe_mkdir "$DOTFILES_LOG_DIR"
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
path_dedupe() {
  # POSIX parameter-expansion walk. Do NOT use `for segment in $current` — zsh
  # does not word-split unquoted parameters, so that form silently no-ops under
  # zsh and duplicate PATH entries survive. This shape is identical in
  # bash, zsh and dash.
  local remaining="${PATH:-}" normalized="" segment
  [ -n "$remaining" ] || return 0
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
# Order below is intentionally lowest-priority first; final PATH has
# highest-priority entries at the front after dedupe.
# 1. System dirs (including NixOS system profile /run/current-system/sw/bin
#    and user nix profile ~/.nix-profile/bin if present)
# 2. Foundry (if installed)
# 3. User bins
# 4. mise shims (highest priority)
for dir in \
  "/nix/var/nix/profiles/default/bin" \
  "$HOME/.nix-profile/bin" \
  "/sbin" \
  "/usr/sbin" \
  "/bin" \
  "/usr/bin" \
  "/run/current-system/sw/bin" \
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

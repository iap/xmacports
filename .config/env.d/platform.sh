#!/bin/bash
# Platform-environment configuration

set -u

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" > /dev/null 2>&1; }

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if [[ -n "${DOTFILES_ENV_LOADED:-}" ]]; then
  return 0
fi
export DOTFILES_ENV_LOADED=1

unset MACPORTS_PREFIX CPPFLAGS LDFLAGS

# Foundry (Ethereum) - optional local installs only
unset FOUNDRY_BIN_PATH
for foundry_path in "$HOME/.foundry/bin" "$HOME/.config/.foundry/bin"; do
  if [[ -d "$foundry_path" ]] && [[ -r "$foundry_path" ]]; then
    export FOUNDRY_BIN_PATH="$foundry_path"
    break
  fi
done

export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-$EDITOR}"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

MAKE_JOBS=""
if has_cmd nproc; then
  MAKE_JOBS=$(nproc 2> /dev/null || echo 2)
elif [[ -f /proc/cpuinfo ]]; then
  MAKE_JOBS=$(grep -c ^processor /proc/cpuinfo 2> /dev/null || echo 2)
else
  MAKE_JOBS=2
fi
export MAKEFLAGS="-j$MAKE_JOBS"

if has_cmd gpgconf; then
  _gpg_ssh_socket=$(gpgconf --list-dirs agent-ssh-socket 2> /dev/null)
  if [[ -n "$_gpg_ssh_socket" ]] && [[ -S "$_gpg_ssh_socket" ]]; then
    export SSH_AUTH_SOCK="$_gpg_ssh_socket"
  fi
  unset _gpg_ssh_socket
fi
if [[ -t 0 ]]; then
  GPG_TTY_VALUE=$(tty 2> /dev/null || echo /dev/tty)
  export GPG_TTY="$GPG_TTY_VALUE"
else
  export GPG_TTY=/dev/tty
fi

safe_mkdir() {
  mkdir -p "$1" 2> /dev/null && chmod 700 "$1" 2> /dev/null || true
}
safe_mkdir "$XDG_CACHE_HOME/logs"
safe_mkdir "$XDG_CACHE_HOME/ssh"
safe_mkdir "$XDG_STATE_HOME/shell"

# ls colors (GNU vs BSD)
if ls --color=auto > /dev/null 2>&1; then
  alias ls='ls --color=auto'
  alias ll='ls -alF --color=auto'
  alias la='ls -A --color=auto'
fi

# grep colors (GNU)
if grep --color=auto "" /dev/null > /dev/null 2>&1; then
  alias grep='grep --color=auto'
fi

umask 077

export DOTNET_CLI_TELEMETRY_OPTOUT=1 HOMEBREW_NO_ANALYTICS=1
export NEXT_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1
export DISABLE_TELEMETRY=1 NO_UPDATE_NOTIFIER=1

path_dedupe() {
  local current="${PATH:-}" normalized="" segment
  local IFS=':'
  for segment in $current; do
    [[ -n "$segment" ]] || continue
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

path_dedupe

for dir in \
  "$HOME/bin" \
  "$HOME/.local/bin" \
  "${FOUNDRY_BIN_PATH:-}" \
  "/usr/local/bin" \
  "/usr/local/sbin" \
  "/usr/bin" \
  "/bin" \
  "/usr/sbin" \
  "/sbin"; do
  path_prepend_if_present "$dir"
done

path_dedupe
export PATH

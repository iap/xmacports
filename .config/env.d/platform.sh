#!/bin/bash
# Platform-environment configuration

set -u

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

[[ -n "$DOTFILES_ENV_LOADED" ]] && return 0
export DOTFILES_ENV_LOADED=1

# MacPorts (macOS only, must be accessible)
if is_macos && has_cmd port && [[ -w "/opt/local" ]]; then
    export MACPORTS_PREFIX="$(command -v port | sed 's|/bin/port||')"
    export CPPFLAGS="-I$MACPORTS_PREFIX/include"
    export LDFLAGS="-L$MACPORTS_PREFIX/lib"
fi

# Foundry (Ethereum - check both standard locations)
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

if has_cmd nproc; then
    export MAKEFLAGS="-j$(nproc 2>/dev/null || echo 2)"
elif [[ -f /proc/cpuinfo ]]; then
    export MAKEFLAGS="-j$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)"
else
    export MAKEFLAGS="-j2"
fi

if has_cmd gpgconf; then
    _gpg_ssh_socket="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)"
    if [[ -n "$_gpg_ssh_socket" ]] && [[ -S "$_gpg_ssh_socket" ]]; then
        export SSH_AUTH_SOCK="$_gpg_ssh_socket"
    fi
    unset _gpg_ssh_socket
fi
[[ -t 0 ]] && export GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)" || export GPG_TTY=/dev/tty

safe_mkdir() {
    mkdir -p "$1" 2>/dev/null && chmod 700 "$1" 2>/dev/null || true
}
safe_mkdir "$XDG_CACHE_HOME/logs"
safe_mkdir "$XDG_CACHE_HOME/ssh"
safe_mkdir "$XDG_STATE_HOME/shell"

# ls colors (GNU vs BSD)
if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
fi

# grep colors (GNU)
if grep --color=auto "" /dev/null >/dev/null 2>&1; then
    alias grep='grep --color=auto'
fi

umask 077

export DOTNET_CLI_TELEMETRY_OPTOUT=1 HOMEBREW_NO_ANALYTICS=1
export NEXT_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1
export DISABLE_TELEMETRY=1 NO_UPDATE_NOTIFIER=1

PATH_CLEAN="$HOME/bin:$HOME/.local/bin"
if is_macos && [[ -n "$MACPORTS_PREFIX" ]] && [[ -d "$MACPORTS_PREFIX" ]]; then
    # Add MacPorts paths without duplication
    for mp_dir in "$MACPORTS_PREFIX/libexec/gnubin" "$MACPORTS_PREFIX/bin" "$MACPORTS_PREFIX/sbin"; do
        [[ -d "$mp_dir" ]] && PATH_CLEAN="$mp_dir:$PATH_CLEAN"
    done
fi
if [[ -n "$FOUNDRY_BIN_PATH" ]]; then
    PATH_CLEAN="$FOUNDRY_BIN_PATH:$PATH_CLEAN"
fi
for dir in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
    [[ -d "$dir" ]] && PATH_CLEAN="$PATH_CLEAN:$dir"
done
export PATH="$PATH_CLEAN"
unset PATH_CLEAN
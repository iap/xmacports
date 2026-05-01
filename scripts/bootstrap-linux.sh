#!/bin/bash
# Linux-specific bootstrap steps
# Called by bootstrap.sh on Linux only

set -e

# Detect package manager
_pkg_manager() {
  if command -v apt-get > /dev/null 2>&1; then
    echo "apt"
  elif command -v dnf > /dev/null 2>&1; then
    echo "dnf"
  elif command -v pacman > /dev/null 2>&1; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

PKG="$(_pkg_manager)"

# Dependency warnings with distro-appropriate install hints
_warn_missing() {
  local cmd="$1" pkg_apt="$2" pkg_dnf="$3" pkg_pac="$4"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    case "$PKG" in
      apt) echo "⚠️  $cmd not found. Install: sudo apt-get install $pkg_apt" ;;
      dnf) echo "⚠️  $cmd not found. Install: sudo dnf install $pkg_dnf" ;;
      pacman) echo "⚠️  $cmd not found. Install: sudo pacman -S $pkg_pac" ;;
      *) echo "⚠️  $cmd not found. Install it via your package manager." ;;
    esac
  fi
}

_warn_missing git git git git
_warn_missing gpgconf gnupg2 gnupg2 gnupg
_warn_missing pinentry-curses libpinentry-curses pinentry-curses pinentry
_warn_missing shellcheck shellcheck ShellCheck shellcheck
_warn_missing shfmt "shfmt (via go)" shfmt shfmt
_warn_missing nano nano nano nano

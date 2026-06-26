#!/bin/bash
# macOS bootstrap steps

set -eu

MACOS_VERSION="$(sw_vers -productVersion 2> /dev/null || echo 0)"
MIN_MACOS_VERSION="10.15"

_version_ge() {
  local a="$1" b="$2" i
  local -a av bv
  IFS='.' read -r -a av <<< "$a"
  IFS='.' read -r -a bv <<< "$b"
  for ((i = ${#av[@]}; i < ${#bv[@]}; i++)); do av[i]=0; done
  for ((i = 0; i < ${#av[@]}; i++)); do
    [[ -z ${bv[i]} ]] && bv[i]=0
    if ((10#${av[i]} > 10#${bv[i]})); then return 0; fi
    if ((10#${av[i]} < 10#${bv[i]})); then return 1; fi
  done
  return 0
}

if ! _version_ge "$MACOS_VERSION" "$MIN_MACOS_VERSION"; then
  echo "⚠️  macOS $MACOS_VERSION detected (minimum supported: $MIN_MACOS_VERSION)"
  echo "Proceeding, but some features may not work."
fi

if ! xcode-select -p > /dev/null 2>&1; then
  echo "Xcode Command Line Tools not found. Installing..."
  xcode-select --install || true
fi

if ! command -v port > /dev/null 2>&1; then
  echo "⚠️  MacPorts not found."
  echo "Install from: https://www.macports.org/install.php"
  echo "Then run: sudo port selfupdate"
else
  if ! port installed coreutils 2> /dev/null | grep -q "coreutils"; then
    echo "Installing coreutils via MacPorts..."
    sudo port selfupdate
    sudo port install coreutils
  fi
fi

if ! command -v gpgconf > /dev/null 2>&1; then
  echo "⚠️  gpgconf not found. Install: sudo port install gnupg2"
fi
if ! [ -x "/Applications/MacPorts/pinentry-mac.app/Contents/MacOS/pinentry-mac" ] &&
  ! command -v pinentry-mac > /dev/null 2>&1 &&
  ! command -v pinentry-curses > /dev/null 2>&1; then
  echo "⚠️  pinentry not found. Install: sudo port install pinentry-mac"
fi

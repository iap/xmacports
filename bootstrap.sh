#!/bin/bash
# Simple dotfiles bootstrap for MacBook Air 2017

set -e

echo "Bootstrapping dotfiles for MacBook Air 2017..."

# Platform check (macOS-only workflow)
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "⚠️  This bootstrap is optimized for macOS with MacPorts."
  echo "Proceeding anyway, but some steps may not apply."
else
  # macOS version check (minimum 10.15)
  MACOS_VERSION="$(sw_vers -productVersion 2> /dev/null || echo 0)"
  MIN_MACOS_VERSION="10.15"
  version_ge() {
    local a="$1" b="$2"
    local i
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
  if ! version_ge "$MACOS_VERSION" "$MIN_MACOS_VERSION"; then
    echo "⚠️  macOS $MACOS_VERSION detected (minimum supported $MIN_MACOS_VERSION)."
    echo "Proceeding, but some features may not work."
  fi

  # Xcode Command Line Tools
  if ! xcode-select -p > /dev/null 2>&1; then
    echo "Xcode Command Line Tools not found. Installing..."
    xcode-select --install || true
  fi

  # MacPorts
  if ! command -v port > /dev/null 2>&1; then
    echo "MacPorts not found."
    echo "Install from: https://www.macports.org/install.php"
    echo "After install, run: sudo port selfupdate"
  else
    # Coreutils
    if ! port installed coreutils 2> /dev/null | grep -q "coreutils"; then
      echo "Installing coreutils via MacPorts..."
      sudo port selfupdate
      sudo port install coreutils
    fi
  fi
fi

# Dependency checks (warn only)
if ! command -v port > /dev/null 2>&1; then
  echo "⚠️  MacPorts (port) not found. Install MacPorts before using this setup."
fi
if ! command -v gpgconf > /dev/null 2>&1; then
  echo "⚠️  gpgconf not found. Install GnuPG (gnupg2) for GPG/SSH integration."
fi
if ! [ -x "/Applications/MacPorts/pinentry-mac.app/Contents/MacOS/pinentry-mac" ] &&
  ! command -v pinentry-mac > /dev/null 2>&1 &&
  ! command -v pinentry-curses > /dev/null 2>&1; then
  echo "⚠️  pinentry not found. Install pinentry-mac (or pinentry-curses) via MacPorts."
fi

# Create backup directory (lazy — only used if needed)
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
_backup_used=0

# Function to backup and link
backup_and_link() {
  local source="$1"
  local target="$2"

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      local current
      current="$(readlink "$target")"
      if [[ "$current" == "$source" ]]; then
        echo "Link already correct: $target -> $source"
        return 0
      fi
    fi
    [[ $_backup_used -eq 0 ]] && mkdir -p "$BACKUP_DIR" && _backup_used=1
    echo "Backing up existing $target"
    mv "$target" "$BACKUP_DIR/"
  fi

  echo "Linking $target -> $source"
  ln -sf "$source" "$target"
}

# Bootstrap dotfiles
backup_and_link "$HOME/.dotfiles/.profile" "$HOME/.profile"
backup_and_link "$HOME/.dotfiles/.zprofile" "$HOME/.zprofile"
backup_and_link "$HOME/.dotfiles/.zshrc" "$HOME/.zshrc"
backup_and_link "$HOME/.dotfiles/.bashrc" "$HOME/.bashrc"
backup_and_link "$HOME/.dotfiles/.gitconfig" "$HOME/.gitconfig"
backup_and_link "$HOME/.dotfiles/.gitignore_global" "$HOME/.gitignore_global"
backup_and_link "$HOME/.dotfiles/.forward" "$HOME/.forward"

# Create directories if they don't exist
mkdir -p "$HOME/bin"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.gnupg"
mkdir -p "$HOME/.ssh"

# Set proper directory permissions
chmod 700 "$HOME/.gnupg"
chmod 700 "$HOME/.ssh"

# Link GPG configuration files
backup_and_link "$HOME/.dotfiles/.config/gpg/gpg.conf" "$HOME/.gnupg/gpg.conf"
backup_and_link "$HOME/.dotfiles/.config/gpg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
backup_and_link "$HOME/.dotfiles/.vimrc" "$HOME/.vimrc"
backup_and_link "$HOME/.dotfiles/.config/ssh/config" "$HOME/.ssh/config"

# Set proper file permissions
chmod 600 "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf"
chmod 600 "$HOME/.ssh/config"

echo "✅ Dotfiles bootstrapped successfully!"
[[ $_backup_used -eq 1 ]] && echo "📁 Backup created at: $BACKUP_DIR"
echo "🔄 Restart your shell or run: source ~/.bashrc"

# Configure repo-local git hooks (if in repo)
if [[ -d "$HOME/.dotfiles/.githooks" ]]; then
  git -C "$HOME/.dotfiles" config core.hooksPath .githooks
fi

# Check if local config files exist
if [[ ! -f "$HOME/.bashrc.local" ]]; then
  echo "💡 Consider creating $HOME/.bashrc.local for personal bash customizations"
fi
if [[ ! -f "$HOME/.zshrc.local" ]]; then
  echo "💡 Consider creating $HOME/.zshrc.local for personal zsh customizations"
fi

if [[ ! -f "$HOME/.gitconfig.local" ]]; then
  echo "💡 Consider creating $HOME/.gitconfig.local with your git user info"
fi

if [[ ! -f "$HOME/.forward.local" ]]; then
  echo "💡 Consider creating $HOME/.forward.local for private mail forwarding"
fi

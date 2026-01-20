#!/bin/bash
# Simple dotfiles bootstrap for MacBook Air 2017

set -e

echo "Bootstrapping dotfiles for MacBook Air 2017..."

# Create backup directory
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Function to backup and link
backup_and_link() {
    local source="$1"
    local target="$2"
    
    if [[ -e "$target" && ! -L "$target" ]]; then
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
echo "📁 Backup created at: $BACKUP_DIR"
echo "🔄 Restart your shell or run: source ~/.zshrc"

# Check if local config files exist
if [[ ! -f "$HOME/.zshrc.local" ]]; then
echo "💡 Consider creating $HOME/.zshrc.local for personal customizations"
fi

if [[ ! -f "$HOME/.gitconfig.local" ]]; then
echo "💡 Consider creating $HOME/.gitconfig.local with your git user info"
fi

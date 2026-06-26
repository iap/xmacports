#!/bin/bash
# Dotfiles bootstrap — platform-aware orchestrator

set -eu

DOTFILES="$HOME/.dotfiles"
OS="$(uname -s)"

echo "Bootstrapping dotfiles (${OS})..."

case "$OS" in
  Darwin)
    bash "$DOTFILES/scripts/bootstrap-macos.sh"
    ;;
  Linux)
    bash "$DOTFILES/scripts/bootstrap-linux.sh"
    ;;
  *)
    echo "⚠️  Unsupported platform: $OS — proceeding with common steps only"
    ;;
esac

# Common: backup and link helper
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
_backup_used=0

backup_and_link() {
  local source="$1" target="$2"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      local current
      current="$(readlink "$target")"
      if [[ "$current" == "$source" ]]; then
        echo "already linked: $target"
        return 0
      fi
    fi
    [[ $_backup_used -eq 0 ]] && mkdir -p "$BACKUP_DIR" && _backup_used=1
    echo "backing up: $target"
    mv "$target" "$BACKUP_DIR/"
  fi
  echo "linking: $target -> $source"
  ln -sf "$source" "$target"
}

# Common: shell configs
backup_and_link "$DOTFILES/.profile" "$HOME/.profile"
backup_and_link "$DOTFILES/.bash_profile" "$HOME/.bash_profile"
backup_and_link "$DOTFILES/.bashrc" "$HOME/.bashrc"
backup_and_link "$DOTFILES/.zprofile" "$HOME/.zprofile"
backup_and_link "$DOTFILES/.zshrc" "$HOME/.zshrc"
backup_and_link "$DOTFILES/.gitconfig" "$HOME/.gitconfig"
backup_and_link "$DOTFILES/.gitignore_global" "$HOME/.gitignore_global"
backup_and_link "$DOTFILES/.forward" "$HOME/.forward"

# Common: directories
mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/.gnupg" "$HOME/.ssh"
chmod 700 "$HOME/.gnupg" "$HOME/.ssh"

# Common: GPG, vim, SSH
backup_and_link "$DOTFILES/.config/gpg/gpg.conf" "$HOME/.gnupg/gpg.conf"
backup_and_link "$DOTFILES/.config/gpg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
backup_and_link "$DOTFILES/.vimrc" "$HOME/.vimrc"
backup_and_link "$DOTFILES/.config/ssh/config" "$HOME/.ssh/config"

chmod 600 "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf"
chmod 600 "$HOME/.ssh/config"

# Common: git hooks
if [[ -d "$DOTFILES/.githooks" ]]; then
  git -C "$DOTFILES" config core.hooksPath .githooks
fi

echo "✅ Dotfiles bootstrapped successfully!"
[[ $_backup_used -eq 1 ]] && echo "📁 Backup: $BACKUP_DIR"
echo "🔄 Restart your shell or run: source ~/.bashrc"

# Local config hints
[[ ! -f "$HOME/.bashrc.local" ]] && echo "💡 Create ~/.bashrc.local for personal bash settings"
[[ ! -f "$HOME/.zshrc.local" ]] && echo "💡 Create ~/.zshrc.local for personal zsh settings"
[[ ! -f "$HOME/.gitconfig.local" ]] && echo "💡 Create ~/.gitconfig.local with your git user info"
[[ ! -f "$HOME/.forward.local" ]] && echo "💡 Create ~/.forward.local for private mail forwarding"

# Private overlay (Keybase)
if [[ -f "$DOTFILES/bootstrap-private.sh" ]]; then
  echo ""
  echo "Bootstrapping private overlay..."
  bash "$DOTFILES/bootstrap-private.sh" || echo "⚠️  Private overlay skipped (Keybase unavailable)"
fi

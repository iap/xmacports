#!/bin/bash
# ZSH cleanup

set -eu

CLEANUP_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/logs/zsh-cleanup-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$CLEANUP_LOG")"

log_action() {
  local action="$1"
  local file="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $action: $file" | tee -a "$CLEANUP_LOG"
}

echo "ZSH Files Cleanup for Development Environment"
echo "This will remove unused .zsh files while preserving essential ones"
echo

KEEP_FILES=(
  "$HOME/.zshrc"       # Current zshrc (symlink to dotfiles)
  "$HOME/.zprofile"    # Login shell profile
  "$HOME/.zsh_history" # Command history
)

REMOVE_FILES=()
while IFS= read -r -d '' f; do
  REMOVE_FILES+=("$f")
done < <(find "$HOME" -maxdepth 1 \( \
  -name '.zshrc.backup.*' \
  -o -name '.zshrc.local.backup.*' \
  -o -name '.zshrc.local.template' \
  \) -print0 2> /dev/null)

echo "Files to KEEP (essential):"
for file in "${KEEP_FILES[@]}"; do
  if [[ -e "$file" ]]; then
    if [[ -L "$file" ]]; then
      echo "  [keep] $file -> $(readlink "$file")"
    else
      echo "  [keep] $file"
    fi
  else
    echo "  [missing] $file"
  fi
done

echo
echo "Files to REMOVE (unused backups/templates):"
for file in "${REMOVE_FILES[@]}"; do
  if [[ -e "$file" ]]; then
    echo "  [remove] $file"
  else
    echo "  [gone]   $file"
  fi
done

echo
echo "ZSH completion cache:"
if [[ -f "$HOME/.zcompdump" ]]; then
  echo "  .zcompdump ($(du -h ~/.zcompdump | cut -f1)) - will regenerate automatically"
else
  echo "  .zcompdump (not found)"
fi

echo
echo "ZSH sessions directory:"
if [[ -d "$HOME/.zsh_sessions" ]]; then
  session_count=$(find ~/.zsh_sessions -name "*.session" | wc -l | tr -d ' ')
  history_count=$(find ~/.zsh_sessions -name "*.history" | wc -l | tr -d ' ')
  echo "  $session_count session files, $history_count history files"
  echo "  (Terminal.app session data - safe to clean old ones)"
else
  echo "  .zsh_sessions (not found)"
fi

echo
read -p "Proceed with cleanup? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Starting cleanup..."

  for file in "${REMOVE_FILES[@]}"; do
    if [[ -e "$file" ]]; then
      rm -f "$file"
      log_action "REMOVED" "$file"
      echo "  Removed $file"
    fi
  done

  # Clean .zcompdump (will regenerate)
  if [[ -f "$HOME/.zcompdump" ]]; then
    rm -f "$HOME/.zcompdump"
    log_action "REMOVED" ".zcompdump (will regenerate)"
    echo "  Removed .zcompdump (will regenerate automatically)"
  fi

  # Clean old zsh sessions (keep last 30 days)
  if [[ -d "$HOME/.zsh_sessions" ]]; then
    old_sessions=$(find ~/.zsh_sessions -name "*.session" -mtime +30 2> /dev/null | wc -l | tr -d ' ')
    old_histories=$(find ~/.zsh_sessions -name "*.history" -mtime +30 2> /dev/null | wc -l | tr -d ' ')

    if [[ $old_sessions -gt 0 || $old_histories -gt 0 ]]; then
      find ~/.zsh_sessions -name "*.session" -mtime +30 -delete 2> /dev/null || true
      find ~/.zsh_sessions -name "*.history" -mtime +30 -delete 2> /dev/null || true
      log_action "CLEANED" ".zsh_sessions (removed $old_sessions sessions, $old_histories histories older than 30 days)"
      echo "  Cleaned old session data ($old_sessions sessions, $old_histories histories)"
    else
      echo "  No old session data to clean"
    fi
  fi

  echo
  echo "Cleanup completed successfully."
  echo "Log saved to: $CLEANUP_LOG"
  echo
  echo "Next steps:"
  echo "  - Restart your terminal to regenerate .zcompdump"
  echo "  - Your command history and current config are preserved"

else
  echo "Cleanup cancelled."
  log_action "CANCELLED" "User cancelled cleanup"
fi

echo
echo "Current ZSH files:"
find ~ -maxdepth 1 -name "*zsh*" -o -name ".zcomp*" | sort

#!/bin/bash
# Uninstall cleanup job

set -eu

# Load platform detection
if [[ -f "$HOME/.dotfiles/shared/platform.sh" ]]; then
  source "$HOME/.dotfiles/shared/platform.sh"
fi

if is_macos; then
  PLIST="$HOME/Library/LaunchAgents/com.iap.dotfiles.cleanup.plist"
  launchctl unload "$PLIST" > /dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "Removed launchd job: com.iap.dotfiles.cleanup"
else
  SCRIPT="${DOTFILES_ROOT:-$HOME/.dotfiles}/scripts/cleanup-7d.sh"
  crontab -l 2> /dev/null | grep -v -F "$SCRIPT" | crontab -
  echo "Removed cron job for: $SCRIPT"
fi

#!/bin/bash
# Uninstall cleanup job

set -eu

# Load platform detection
DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
if [[ -f "$DOTFILES_ROOT/shared/platform.sh" ]]; then
  source "$DOTFILES_ROOT/shared/platform.sh"
fi

if is_macos; then
  PLIST="$HOME/Library/LaunchAgents/com.iap.dotfiles.cleanup.plist"
  launchctl unload "$PLIST" > /dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "Removed launchd job: com.iap.dotfiles.cleanup"
else
  SCRIPT="${DOTFILES_ROOT}/scripts/cleanup.sh"
  crontab -l 2> /dev/null | grep -v -F "$SCRIPT" | crontab -
  echo "Removed cron job for: $SCRIPT"
fi

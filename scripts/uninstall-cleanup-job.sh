#!/bin/bash
# Uninstall scheduled cleanup job (launchd on macOS, cron on Linux).

set -e

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.iap.dotfiles.cleanup.plist"
  launchctl unload "$PLIST" > /dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "Removed launchd job: com.iap.dotfiles.cleanup"
else
  SCRIPT="$HOME/.dotfiles/scripts/cleanup-7d.sh"
  crontab -l 2> /dev/null | grep -v -F "$SCRIPT" | crontab -
  echo "Removed cron job for: $SCRIPT"
fi

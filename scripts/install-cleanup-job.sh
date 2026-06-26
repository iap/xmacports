#!/bin/bash
# Install cleanup job

set -eu

SCRIPT="$HOME/.dotfiles/scripts/cleanup-7d.sh"
if [ ! -x "$SCRIPT" ]; then
  echo "cleanup script not found or not executable: $SCRIPT" >&2
  exit 1
fi

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.iap.dotfiles.cleanup.plist"
  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.iap.dotfiles.cleanup</string>
    <key>ProgramArguments</key>
    <array>
      <string>$SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key>
      <integer>3</integer>
      <key>Minute</key>
      <integer>17</integer>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.cache/logs/dotfiles-cleanup.out</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.cache/logs/dotfiles-cleanup.err</string>
  </dict>
</plist>
EOF
  launchctl unload "$PLIST" > /dev/null 2>&1 || true
  launchctl load "$PLIST"
  echo "Installed launchd job: com.iap.dotfiles.cleanup"
else
  CRON_LINE="17 3 * * * $SCRIPT"
  (
    crontab -l 2> /dev/null | grep -v -F "$SCRIPT"
    echo "$CRON_LINE"
  ) | crontab -
  echo "Installed cron job: $CRON_LINE"
fi

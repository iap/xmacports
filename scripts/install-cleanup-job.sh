#!/bin/bash
# Install cleanup job

set -eu

# Load platform detection
if [[ -f "$HOME/.dotfiles/shared/platform.sh" ]]; then
  source "$HOME/.dotfiles/shared/platform.sh"
fi

SCRIPT="${DOTFILES_ROOT:-$HOME/.dotfiles}/scripts/cleanup-7d.sh"
if [ ! -x "$SCRIPT" ]; then
  echo "cleanup script not found or not executable: $SCRIPT" >&2
  exit 1
fi

if is_macos; then
  PLIST="$HOME/Library/LaunchAgents/com.iap.dotfiles.cleanup.plist"
  LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/logs"
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
    <string>$LOG_DIR/dotfiles-cleanup.out</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/dotfiles-cleanup.err</string>
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

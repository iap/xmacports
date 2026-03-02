#!/bin/bash
# Cleanup dotfiles backups, logs, and shell history older than 7 days.

set -e

RANDOM_DELAY_MAX=3600
sleep $((RANDOM % RANDOM_DELAY_MAX))

NOW_EPOCH=$(date +%s)
CUTOFF=$((NOW_EPOCH - 7 * 24 * 60 * 60))

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/dotfiles-cleanup-$(date +%Y-%m-%d).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting cleanup (cutoff epoch: $CUTOFF)"

# Dotfiles backups
find "$HOME" -maxdepth 1 -type d -name ".dotfiles-backup-*" -mtime +7 -print0 |
  while IFS= read -r -d '' d; do
    log "Removing backup dir: $d"
    rm -rf "$d"
  done

# Logs
for d in "$HOME/.logs" "$LOG_DIR"; do
  if [ -d "$d" ]; then
    find "$d" -type f -mtime +7 -print0 |
      while IFS= read -r -d '' f; do
        log "Removing log: $f"
        rm -f "$f"
      done
  fi
done

# ZSH history (extended history format required)
ZSH_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
if [ -f "$ZSH_HISTORY" ]; then
  if grep -qE '^: [0-9]+' "$ZSH_HISTORY"; then
    log "Pruning ZSH history: $ZSH_HISTORY"
    awk -v cutoff="$CUTOFF" '
      /^: [0-9]+:/ {
        split($2, a, ":");
        ts = a[1] + 0;
        if (ts >= cutoff) { print; keep=1 } else { keep=0 }
        next
      }
      { if (keep) print }
    ' "$ZSH_HISTORY" > "$ZSH_HISTORY.tmp"
    mv "$ZSH_HISTORY.tmp" "$ZSH_HISTORY"
  else
    log "Skipping ZSH history prune (no timestamps): $ZSH_HISTORY"
  fi
else
  log "ZSH history not found: $ZSH_HISTORY"
fi

# Bash history (timestamp format required)
BASH_HISTORY="${HISTFILE:-$HOME/.bash_history}"
if [ -f "$BASH_HISTORY" ]; then
  if grep -qE '^#[0-9]+' "$BASH_HISTORY"; then
    log "Pruning Bash history: $BASH_HISTORY"
    awk -v cutoff="$CUTOFF" '
      /^#[0-9]+$/ { ts = substr($0,2) + 0; keep = (ts >= cutoff); if (keep) print; next }
      { if (keep) print }
    ' "$BASH_HISTORY" > "$BASH_HISTORY.tmp"
    mv "$BASH_HISTORY.tmp" "$BASH_HISTORY"
  else
    log "Skipping Bash history prune (no timestamps): $BASH_HISTORY"
  fi
else
  log "Bash history not found: $BASH_HISTORY"
fi

log "Cleanup complete"

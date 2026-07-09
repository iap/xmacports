#!/bin/bash
# Unified cleanup script — consolidates cleanup-7d.sh, cleanup-zsh.sh, and benchmark.sh

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/logs"
CUTOFF=$(date -d '7 days ago' +%s 2> /dev/null || date -v-7d +%s 2> /dev/null || echo $(($(date +%s) - 604800)))

# Load platform detection
if [[ -f "$DOTFILES_ROOT/shared/platform.sh" ]]; then
  source "$DOTFILES_ROOT/shared/platform.sh"
fi

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $1" | tee -a "$CLEANUP_LOG"
}

safe_under_home() {
  local path="$1"
  [[ "$path" == "$HOME"/* ]] || [[ "$path" == "$HOME" ]]
}

# --- 7-day cleanup ---
cleanup_7d() {
  echo "=== 7-Day Cleanup ==="

  # Backup dirs
  if [[ -d "$HOME" ]]; then
    find "$HOME" -maxdepth 1 -type d -name ".dotfiles-backup-*" -mtime +7 -print0 2> /dev/null |
      while IFS= read -r -d '' d; do
        if safe_under_home "$d"; then
          log "Removing backup dir: $d"
          rm -rf "$d"
        else
          log "Skipping unexpected path: $d"
        fi
      done
  fi

  # Logs
  if [[ -d "$LOG_DIR" ]]; then
    find "$LOG_DIR" -type f -mtime +7 -print0 2> /dev/null |
      while IFS= read -r -d '' f; do
        if safe_under_home "$f"; then
          log "Removing log: $f"
          rm -f "$f"
        else
          log "Skipping unexpected path: $f"
        fi
      done
  fi

  # ZSH history (extended history format required)
  ZSH_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
  if [[ -f "$ZSH_HISTORY" ]] && grep -qE '^: [0-9]+' "$ZSH_HISTORY"; then
    log "Pruning ZSH history: $ZSH_HISTORY"
    tmpfile=$(mktemp "${ZSH_HISTORY}.tmp.XXXXXX")
    awk -v cutoff="$CUTOFF" '
      /^: [0-9]+:/ {
        split($2, a, ":");
        ts = a[1] + 0;
        if (ts >= cutoff) { print; keep=1 } else { keep=0 }
        next
      }
      { if (keep) print }
    ' "$ZSH_HISTORY" > "$tmpfile"
    mv "$tmpfile" "$ZSH_HISTORY"
  elif [[ -f "$ZSH_HISTORY" ]]; then
    log "Skipping ZSH history prune (no timestamps): $ZSH_HISTORY"
  fi

  # Bash history (timestamp format required)
  BASH_HISTORY="${HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/bash/history}"
  if [[ -f "$BASH_HISTORY" ]] && grep -qE '^#[0-9]+' "$BASH_HISTORY"; then
    log "Pruning Bash history: $BASH_HISTORY"
    tmpfile=$(mktemp "${BASH_HISTORY}.tmp.XXXXXX")
    awk -v cutoff="$CUTOFF" '
      /^#[0-9]+$/ { ts = substr($0,2) + 0; keep = (ts >= cutoff); if (keep) print; next }
      { if (keep) print }
    ' "$BASH_HISTORY" > "$tmpfile"
    mv "$tmpfile" "$BASH_HISTORY"
  elif [[ -f "$BASH_HISTORY" ]]; then
    log "Skipping Bash history prune (no timestamps): $BASH_HISTORY"
  fi

  # Shell prompt caches
  SHELL_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/shell"
  if [[ -d "$SHELL_CACHE_DIR" ]]; then
    old_caches=$(find "$SHELL_CACHE_DIR" -name 'git_status_*' -mtime +1 2> /dev/null | wc -l | tr -d ' ')
    if [[ "$old_caches" -gt 0 ]]; then
      find "$SHELL_CACHE_DIR" -name 'git_status_*' -mtime +1 -delete 2> /dev/null || true
      log "Cleaned old prompt caches ($old_caches entries)"
    fi
  fi

  log "7-day cleanup complete"
}

# --- ZSH cleanup ---
cleanup_zsh() {
  echo "=== ZSH Cleanup ==="

  KEEP_FILES=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.zsh_history"
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
    session_count=$(find ~/.zsh_sessions -name "*.session" 2> /dev/null | wc -l | tr -d ' ')
    history_count=$(find ~/.zsh_sessions -name "*.history" 2> /dev/null | wc -l | tr -d ' ')
    echo "  $session_count session files, $history_count history files"
    echo "  (Terminal.app session data - safe to clean old ones)"
  else
    echo "  .zsh_sessions (not found)"
  fi

  echo
  read -p "Proceed with ZSH cleanup? (y/N): " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting ZSH cleanup..."

    for file in "${REMOVE_FILES[@]}"; do
      if [[ -e "$file" ]]; then
        rm -f "$file"
        log "REMOVED: $file"
        echo "  Removed $file"
      fi
    done

    if [[ -f "$HOME/.zcompdump" ]]; then
      rm -f "$HOME/.zcompdump"
      log "REMOVED: .zcompdump (will regenerate)"
      echo "  Removed .zcompdump (will regenerate automatically)"
    fi

    if [[ -d "$HOME/.zsh_sessions" ]]; then
      old_sessions=$(find ~/.zsh_sessions -name "*.session" -mtime +30 2> /dev/null | wc -l | tr -d ' ')
      old_histories=$(find ~/.zsh_sessions -name "*.history" -mtime +30 2> /dev/null | wc -l | tr -d ' ')

      if [[ $old_sessions -gt 0 || $old_histories -gt 0 ]]; then
        find ~/.zsh_sessions -name "*.session" -mtime +30 -delete 2> /dev/null || true
        find ~/.zsh_sessions -name "*.history" -mtime +30 -delete 2> /dev/null || true
        log "CLEANED: .zsh_sessions (removed $old_sessions sessions, $old_histories histories older than 30 days)"
        echo "  Cleaned old session data ($old_sessions sessions, $old_histories histories)"
      else
        echo "  No old session data to clean"
      fi
    fi

    echo
    echo "ZSH cleanup completed successfully."
    echo "Log saved to: $CLEANUP_LOG"
    echo
    echo "Next steps:"
    echo "  - Restart your terminal to regenerate .zcompdump"
    echo "  - Your command history and current config are preserved"
  else
    echo "ZSH cleanup cancelled."
    log "CANCELLED: User cancelled ZSH cleanup"
  fi

  echo
  echo "Current ZSH files:"
  find ~ -maxdepth 1 -name "*zsh*" -o -name ".zcomp*" | sort
}

# --- Benchmark shell startup ---
benchmark() {
  echo "=== Shell Startup Benchmark ==="
  echo "Target: <500ms per shell"

  for shell in bash zsh; do
    if has_cmd "$shell"; then
      echo "Benchmarking $shell startup time..."
      for i in {1..5}; do
        time_result=$(
          TIMEFORMAT='%R'
          { time "$shell" -i -c 'exit' 2> /dev/null; } 2>&1
        )
        echo "  Test $i: ${time_result}s"
      done
      echo
    fi
  done
}

# --- Main ---
CLEANUP_LOG="${LOG_DIR}/cleanup-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$CLEANUP_LOG")"

case "${1:-}" in
  7d)
    cleanup_7d
    ;;
  zsh)
    cleanup_zsh
    ;;
  bench | benchmark)
    benchmark
    ;;
  all | "")
    cleanup_7d
    echo
    cleanup_zsh
    echo
    benchmark
    ;;
  *)
    echo "Usage: $0 [7d|zsh|bench|all]"
    echo "  7d      - 7-day cleanup (backups, logs, history, caches)"
    echo "  zsh     - Interactive ZSH cleanup (backup files, completion, sessions)"
    echo "  bench   - Benchmark bash/zsh startup time"
    echo "  all     - Run all (default)"
    exit 1
    ;;
esac

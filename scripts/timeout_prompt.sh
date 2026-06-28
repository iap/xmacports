#!/bin/bash
# Timeout prompt utilities for interactive scripts

timeout_prompt() {
  local prompt="$1"
  local timeout="${2:-5}"
  local default="${3:-}"
  local answer=""
  if [ -n "$default" ]; then
    prompt="$prompt [$default] "
  else
    prompt="$prompt "
  fi
  read -t "$timeout" -r -p "$prompt" answer || true
  if [ -z "$answer" ]; then
    answer="$default"
  fi
  echo "$answer"
}

timeout_confirm() {
  local prompt="$1"
  local timeout="${2:-5}"
  local default="${3:-n}"
  local answer
  answer=$(timeout_prompt "$prompt" "$timeout" "$default")
  case "$answer" in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

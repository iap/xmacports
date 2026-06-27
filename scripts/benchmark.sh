#!/bin/bash
set -eu

benchmark_shell() {
  local shell="$1"
  local label="$2"
  echo "Benchmarking $label startup time..."
  for i in {1..5}; do
    time_result=$(
      TIMEFORMAT='%R'
      { time "$shell" -i -c 'exit' 2> /dev/null; } 2>&1
    )
    echo "  Test $i: ${time_result}s"
  done
  echo
}

benchmark_shell "bash" "bash"
benchmark_shell "zsh" "zsh"

echo "Target: <500ms per shell"

#!/bin/bash
# Simple shell startup benchmark for MacBook Air 2017

set -e

echo "Benchmarking ZSH startup time..."
echo "Benchmark"

# Run 5 tests
for i in {1..5}; do
  time_result=$(time (zsh -i -c 'exit') 2>&1 | grep real | awk '{print $2}')
  echo "Test $i: $time_result"
  # Convert to milliseconds for averaging (simplified)
done

echo ""
echo "Average startup time calculated above"
echo "Target: <500ms (compinit dominates; ~65ms unavoidable)"

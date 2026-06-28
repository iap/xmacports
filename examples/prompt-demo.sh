#!/bin/bash
# Demonstrate the lightweight PS1 prompt

echo "Lightweight PS1 Prompt Demo"
echo

echo "Prompt Features:"
echo "  - Current directory (shortened if long)"
echo "  - Git branch and status (clean, +/- dirty)"
echo "  - Exit status indicator (red [code] if non-zero)"
echo "  - Minimal colors for readability"
echo

echo "Example prompts:"
echo

echo "Normal directory:"
echo "$HOME/Projects/dotfiles ❯ "
echo

echo "Git repository (clean):"
echo "$HOME/Projects/dotfiles (main) ❯ "
echo

echo "Git repository (dirty):"
echo "$HOME/Projects/dotfiles (main±) ❯ "
echo

echo "After failed command:"
echo "[1] $HOME/Projects/dotfiles (main±) ❯ "
echo

echo "Long path (shortened):"
echo "...very/long/path/to/directory ❯ "
echo

echo "Performance: fast git check, minimal subprocesses, 5s dir cache"

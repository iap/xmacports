#!/bin/bash
# Login shell entry point — sources .bashrc for interactive login shells
# macOS Terminal.app and iTerm open login shells, so .bashrc is not read automatically

[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

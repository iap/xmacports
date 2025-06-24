# Environment variables for Makefile
# Development environment optimized settings

# XDG Base Directory variables
XDG_CONFIG_HOME ?= $(HOME)/.config
XDG_DATA_HOME ?= $(HOME)/.local/share
XDG_CACHE_HOME ?= $(HOME)/.cache
XDG_STATE_HOME ?= $(HOME)/.local/state

# MacPorts specific paths (dynamic detection)
MACPORTS_PREFIX ?= $(shell command -v port 2>/dev/null | sed 's|/bin/port||' || echo '/opt/local')

# Performance settings for efficient builds
MAKEFLAGS ?= -j$(shell sysctl -n hw.ncpu 2>/dev/null || echo 2)

# Logging
LOG_DIR = $(XDG_CACHE_HOME)/logs

# Git settings
GIT_CONFIG_GLOBAL = $(HOME)/.gitconfig
GIT_IGNORE_GLOBAL = $(HOME)/.gitignore_global

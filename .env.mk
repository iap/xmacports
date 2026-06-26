# Environment variables for Makefile

XDG_CONFIG_HOME ?= $(HOME)/.config
XDG_DATA_HOME ?= $(HOME)/.local/share
XDG_CACHE_HOME ?= $(HOME)/.cache
XDG_STATE_HOME ?= $(HOME)/.local/state

MACPORTS_PREFIX ?= $(shell if command -v port >/dev/null 2>&1; then command -v port | sed 's|/bin/port||'; else echo '/opt/local'; fi)

MAKEFLAGS ?= -j$(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
# Some targets may not be parallel-safe; override if needed.

LOG_DIR ?= $(XDG_CACHE_HOME)/logs

GIT_CONFIG_GLOBAL = $(HOME)/.gitconfig
GIT_IGNORE_GLOBAL = $(HOME)/.gitignore_global

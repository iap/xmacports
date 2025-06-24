# Simple Makefile for dotfiles management
# MacBook Air 2017 optimized

.PHONY: bootstrap clean status test help

# Default target
all: bootstrap

# Bootstrap dotfiles
bootstrap:
	@echo "Bootstrapping dotfiles..."
	@./bootstrap.sh

# Remove dotfiles symlinks
clean:
	@echo "Removing dotfiles symlinks..."
	@rm -f "$$HOME/.profile" "$$HOME/.zprofile" "$$HOME/.zshrc" "$$HOME/.bashrc" "$$HOME/.gitconfig" "$$HOME/.gitignore_global" "$$HOME/.gnupg/gpg.conf" "$$HOME/.gnupg/gpg-agent.conf" "$$HOME/.vimrc" "$$HOME/.ssh/config"
	@echo "✅ Dotfiles removed"

# Show installation status
status:
	@echo "Dotfiles Status:"
	@echo "================"
	@if [ -L "$$HOME/.profile" ]; then echo "✅ $$HOME/.profile -> $$(readlink "$$HOME/.profile")"; else echo "❌ $$HOME/.profile not linked"; fi
	@if [ -L "$$HOME/.zprofile" ]; then echo "✅ $$HOME/.zprofile -> $$(readlink "$$HOME/.zprofile")"; else echo "❌ $$HOME/.zprofile not linked"; fi
	@if [ -L "$$HOME/.zshrc" ]; then echo "✅ $$HOME/.zshrc -> $$(readlink "$$HOME/.zshrc")"; else echo "❌ $$HOME/.zshrc not linked"; fi
	@if [ -L "$$HOME/.bashrc" ]; then echo "✅ $$HOME/.bashrc -> $$(readlink "$$HOME/.bashrc")"; else echo "❌ $$HOME/.bashrc not linked"; fi
	@if [ -L "$$HOME/.gitconfig" ]; then echo "✅ $$HOME/.gitconfig -> $$(readlink "$$HOME/.gitconfig")"; else echo "❌ $$HOME/.gitconfig not linked"; fi
	@if [ -L "$$HOME/.gitignore_global" ]; then echo "✅ $$HOME/.gitignore_global -> $$(readlink "$$HOME/.gitignore_global")"; else echo "❌ $$HOME/.gitignore_global not linked"; fi
	@if [ -L "$$HOME/.gnupg/gpg.conf" ]; then echo "✅ $$HOME/.gnupg/gpg.conf -> $$(readlink "$$HOME/.gnupg/gpg.conf")"; else echo "❌ $$HOME/.gnupg/gpg.conf not linked"; fi
	@if [ -L "$$HOME/.gnupg/gpg-agent.conf" ]; then echo "✅ $$HOME/.gnupg/gpg-agent.conf -> $$(readlink "$$HOME/.gnupg/gpg-agent.conf")"; else echo "❌ $$HOME/.gnupg/gpg-agent.conf not linked"; fi
	@if [ -L "$$HOME/.vimrc" ]; then echo "✅ $$HOME/.vimrc -> $$(readlink "$$HOME/.vimrc")"; else echo "❌ $$HOME/.vimrc not linked"; fi
	@if [ -L "$$HOME/.ssh/config" ]; then echo "✅ $$HOME/.ssh/config -> $$(readlink "$$HOME/.ssh/config")"; else echo "❌ $$HOME/.ssh/config not linked"; fi

# Test configuration syntax
test:
	@echo "Testing configurations..."
	@zsh -n .zshrc && echo "✅ ZSH syntax OK" || echo "❌ ZSH syntax error"
	@git config --file .gitconfig --list > /dev/null && echo "✅ Git config OK" || echo "❌ Git config error"

# Run comprehensive test suite
test-all:
	@echo "Running comprehensive test suite..."
	@./tests/run-tests.sh all

# Run specific test types
test-functions:
	@./tests/run-tests.sh functions

test-compliance:
	@./tests/run-tests.sh compliance

# Show help
help:
	@echo "Available targets:"
	@echo "  bootstrap       - Bootstrap dotfiles (default)"
	@echo "  clean           - Remove dotfiles symlinks"
	@echo "  status          - Show bootstrap status"
	@echo "  test            - Test configuration syntax"
	@echo "  test-all        - Run comprehensive test suite"
	@echo "  test-functions  - Run function tests only"
	@echo "  test-compliance - Run compliance tests only"
	@echo "  help            - Show this help"

# Makefile

SHELL := /bin/bash

# Ensure MacPorts tools are available (they may not be in PATH)
MACPORTS_PATH := /opt/local/bin
ifneq ($(shell test -d $(MACPORTS_PATH) && echo yes),)
    export PATH := $(MACPORTS_PATH):$(PATH)
endif

# Include environment variables
-include .env.mk

.PHONY: bootstrap clean status test audit lint shellcheck shfmt fmt check fmt-check test-all test-functions test-compliance verify switch-shell help

bootstrap:
	@echo "Bootstrapping dotfiles..."
	@./bootstrap.sh

clean:
	@echo "⚠️  This will remove all dotfiles symlinks."
	@for f in \
		"$$HOME/.profile" "$$HOME/.bash_profile" "$$HOME/.zprofile" "$$HOME/.zshrc" "$$HOME/.bashrc" \
		"$$HOME/.gitconfig" "$$HOME/.gitignore_global" "$$HOME/.gnupg/gpg.conf" "$$HOME/.gnupg/gpg-agent.conf" \
		"$$HOME/.vimrc" "$$HOME/.ssh/config" "$$HOME/.forward" \
		"$$HOME/.config/vim/vimrc" "$$HOME/.config/vim/privacy.vim" "$$HOME/.config/npm/config"; do \
		if [ -L "$$f" ]; then \
			target=$$(readlink "$$f"); \
			case "$$target" in "$$HOME/.dotfiles"/*) rm -f "$$f" ;; esac; \
		fi; \
	done
	@echo "✅ Dotfiles removed"

status:
	@echo "Dotfiles Status:"
	@echo
	@for f in .profile .bash_profile .zprofile .zshrc .bashrc .gitconfig .gitignore_global .forward \
		.gnupg/gpg.conf .gnupg/gpg-agent.conf .vimrc .ssh/config \
		.config/vim/vimrc .config/vim/privacy.vim .config/npm/config; do \
		if [ -L "$$HOME/$$f" ]; then \
			echo "✅ $$HOME/$$f -> $$(readlink "$$HOME/$$f")"; \
		else \
			echo "❌ $$HOME/$$f not linked"; \
		fi; \
	done

audit:
	@./scripts/audit.sh

test:
	@echo "Testing configurations..."
	@zsh -n .zshrc && echo "✅ ZSH syntax OK" || echo "❌ ZSH syntax error"
	@for f in .zshrc.d/*.sh; do zsh -n "$$f" && echo "✅ $$f syntax OK" || echo "❌ $$f syntax error"; done
	@bash -n .bashrc && echo "✅ Bash syntax OK" || echo "❌ Bash syntax error"
	@bash -n .bash_profile && echo "✅ bash_profile syntax OK" || echo "❌ bash_profile syntax error"
	@bash -n .profile && echo "✅ profile syntax OK" || echo "❌ profile syntax error"
	@zsh -n .zprofile && echo "✅ zprofile syntax OK" || echo "❌ zprofile syntax error"
	@for f in shared/*.sh; do bash -n "$$f" && echo "✅ $$f syntax OK" || echo "❌ $$f syntax error"; done
	@git config --file .gitconfig --list > /dev/null && echo "✅ Git config OK" || echo "❌ Git config error"

shellcheck:
	@echo "Running shellcheck..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "❌ shellcheck not found. Install it manually."; exit 1; }
	@./scripts/shellcheck.sh

shfmt:
	@echo "Running shfmt..."
	@command -v shfmt >/dev/null 2>&1 || { echo "❌ shfmt not found. Install it manually."; exit 1; }
	@./scripts/shfmt.sh

fmt-check:
	@echo "Running shfmt check..."
	@command -v shfmt >/dev/null 2>&1 || { echo "❌ shfmt not found. Install it manually."; exit 1; }
	@./scripts/shfmt.sh --check

fmt: shfmt

lint: shellcheck

check: fmt-check shellcheck

test-all:
	@echo "Running comprehensive test suite..."
	@./tests/run-tests.sh all

verify:
	@echo "Running dotfiles verification..."
	@./tests/verify-dotfiles.sh

test-functions:
	@./tests/run-tests.sh functions

test-compliance:
	@./scripts/compliance-check.sh

# Switch login shell between bash and zsh (platform-aware)
switch-shell:
	@OS=$$(uname -s); \
	CURRENT=$$(dscl . -read $$HOME UserShell 2>/dev/null || getent passwd $$USER | cut -d: -f7); \
	echo "Current login shell: $$CURRENT"; \
	if [ "$$OS" = "Darwin" ]; then \
		case "$$CURRENT" in *zsh*) TARGET=$$(command -v bash) ;; *) TARGET=/bin/zsh ;; esac; \
	else \
		case "$$CURRENT" in *bash*) TARGET=$$(command -v zsh) ;; *) TARGET=$$(command -v bash) ;; esac; \
	fi; \
	[ -z "$$TARGET" ] && { echo "❌ Target shell not found"; exit 1; }; \
	grep -qF "$$TARGET" /etc/shells || { echo "Adding $$TARGET to /etc/shells..."; sudo sh -c "echo $$TARGET >> /etc/shells"; }; \
	chsh -s "$$TARGET" && echo "✅ Login shell set to $$TARGET. Re-login to apply."

help:
	@echo "Available targets:"
	@echo "  bootstrap         - Bootstrap dotfiles (default)"
	@echo "  clean             - Remove dotfiles symlinks"
	@echo "  status            - Show bootstrap status"
	@echo "  audit             - Check file permissions and compliance"
	@echo "  test              - Test configuration syntax"
	@echo "  test-all          - Run comprehensive test suite"
	@echo "  test-functions    - Run function tests only"
	@echo "  test-compliance   - Run compliance tests only"
	@echo "  verify            - Run dotfiles verification"
	@echo "  shellcheck        - Lint shell scripts"
	@echo "  shfmt             - Format shell scripts in place"
	@echo "  fmt-check         - Check formatting without changes"
	@echo "  fmt               - Alias for shfmt"
	@echo "  lint              - Alias for shellcheck"
	@echo "  check             - Run fmt-check and shellcheck"
	@echo "  switch-shell      - Toggle login shell (bash<->zsh, platform-aware)"
	@echo "  help              - Show this help"
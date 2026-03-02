# Simple Makefile for dotfiles management
# MacBook Air 2017 optimized

SHELL := /bin/bash

.PHONY: bootstrap clean status test audit lint shellcheck shfmt shfmt-check fmt schedule-cleanup unschedule-cleanup help

# Default target
all: bootstrap

# Bootstrap dotfiles
bootstrap:
	@echo "Bootstrapping dotfiles..."
	@./bootstrap.sh

# Remove dotfiles symlinks
clean:
	@echo "⚠️  This will remove all dotfiles symlinks. Continue? [y/N]" && read ans && [ $${ans:-N} = y ]
	@echo "Removing dotfiles symlinks..."
	@for f in "$$HOME/.profile" "$$HOME/.zprofile" "$$HOME/.zshrc" "$$HOME/.bashrc" "$$HOME/.gitconfig" "$$HOME/.gitignore_global" "$$HOME/.gnupg/gpg.conf" "$$HOME/.gnupg/gpg-agent.conf" "$$HOME/.vimrc" "$$HOME/.ssh/config" "$$HOME/.forward"; do \
		if [ -L "$$f" ]; then \
			target=$$(readlink "$$f"); \
			case "$$target" in \
				"$$HOME/.dotfiles"/*) rm -f "$$f" ;; \
				*) echo "Skipping $$f (not linked to dotfiles)";; \
			esac; \
		else \
			echo "Skipping $$f (not a symlink)"; \
		fi; \
	done
	@echo "✅ Dotfiles removed"

# Show installation status
status:
	@echo "Dotfiles Status:"
	@echo ""
	@if [ -L "$$HOME/.profile" ]; then echo "✅ $$HOME/.profile -> $$(readlink "$$HOME/.profile")"; else echo "❌ $$HOME/.profile not linked"; fi
	@if [ -L "$$HOME/.zprofile" ]; then echo "✅ $$HOME/.zprofile -> $$(readlink "$$HOME/.zprofile")"; else echo "❌ $$HOME/.zprofile not linked"; fi
	@if [ -L "$$HOME/.zshrc" ]; then echo "✅ $$HOME/.zshrc -> $$(readlink "$$HOME/.zshrc")"; else echo "❌ $$HOME/.zshrc not linked"; fi
	@if [ -L "$$HOME/.bashrc" ]; then echo "✅ $$HOME/.bashrc -> $$(readlink "$$HOME/.bashrc")"; else echo "❌ $$HOME/.bashrc not linked"; fi
	@if [ -L "$$HOME/.gitconfig" ]; then echo "✅ $$HOME/.gitconfig -> $$(readlink "$$HOME/.gitconfig")"; else echo "❌ $$HOME/.gitconfig not linked"; fi
	@if [ -L "$$HOME/.gitignore_global" ]; then echo "✅ $$HOME/.gitignore_global -> $$(readlink "$$HOME/.gitignore_global")"; else echo "❌ $$HOME/.gitignore_global not linked"; fi
	@if [ -L "$$HOME/.forward" ]; then echo "✅ $$HOME/.forward -> $$(readlink "$$HOME/.forward")"; else echo "❌ $$HOME/.forward not linked"; fi
	@if [ -L "$$HOME/.gnupg/gpg.conf" ]; then echo "✅ $$HOME/.gnupg/gpg.conf -> $$(readlink "$$HOME/.gnupg/gpg.conf")"; else echo "❌ $$HOME/.gnupg/gpg.conf not linked"; fi
	@if [ -L "$$HOME/.gnupg/gpg-agent.conf" ]; then echo "✅ $$HOME/.gnupg/gpg-agent.conf -> $$(readlink "$$HOME/.gnupg/gpg-agent.conf")"; else echo "❌ $$HOME/.gnupg/gpg-agent.conf not linked"; fi
	@if [ -L "$$HOME/.vimrc" ]; then echo "✅ $$HOME/.vimrc -> $$(readlink "$$HOME/.vimrc")"; else echo "❌ $$HOME/.vimrc not linked"; fi
	@if [ -L "$$HOME/.ssh/config" ]; then echo "✅ $$HOME/.ssh/config -> $$(readlink "$$HOME/.ssh/config")"; else echo "❌ $$HOME/.ssh/config not linked"; fi

# Check compliance (includes home directory permissions)
audit:
	@set -e; \
	echo "Dotfiles Audit:"; \
	echo ""; \
	if stat --version >/dev/null 2>&1; then \
		perm_of_cmd='stat -c %a'; \
	else \
		perm_of_cmd='stat -f %Lp'; \
	fi; \
	home_perms=$$(eval "$$perm_of_cmd \"$$HOME\"" 2>/dev/null || true); \
	if [ "$$home_perms" = "711" ]; then \
		echo "✅ Home permissions: 711"; \
	else \
		echo "⚠️  Home permissions: $${home_perms:-unknown} (expected 711)"; \
	fi; \
	echo ""; \
	echo "Directory permissions (expect 755):"; \
	find . -maxdepth 2 -type d ! -path "./.git*" -print0 | while IFS= read -r -d '' d; do \
		p=$$(eval "$$perm_of_cmd \"$$d\"" 2>/dev/null || true); \
		if [ "$$p" = "755" ]; then \
			printf "✅ %s %s\n" "$$p" "$$d"; \
		else \
			printf "⚠️  %s %s (expected 755)\n" "$${p:-unknown}" "$$d"; \
		fi; \
	done; \
	echo ""; \
	echo "Executable scripts (expect +x):"; \
	for f in bootstrap.sh bin/* scripts/*.sh tests/*.sh examples/*.sh; do \
		[ -e "$$f" ] || continue; \
		if [ -x "$$f" ]; then \
			echo "✅ $$f"; \
		else \
			echo "⚠️  $$f (not executable)"; \
		fi; \
	done; \
	echo ""; \
	echo "Non-executable configs (should not be +x):"; \
	for f in .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward .zshrc.d/*.sh; do \
		[ -e "$$f" ] || continue; \
		if [ -x "$$f" ]; then \
			echo "⚠️  $$f (executable)"; \
		fi; \
	done; \
	find .config -type f -name "*.sh" -print0 | while IFS= read -r -d '' f; do \
		if [ -x "$$f" ]; then \
			echo "⚠️  $$f (executable)"; \
		fi; \
	done; \
	find .config -type f -name "*.conf" -print0 | while IFS= read -r -d '' f; do \
		if [ -x "$$f" ]; then \
			echo "⚠️  $$f (executable)"; \
		fi; \
	done; \
	echo ""; \
	echo "Config file permissions (expect 644):"; \
	for f in .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward .env.mk MANUAL.md README.md .zshrc.d/*.sh; do \
		[ -e "$$f" ] || continue; \
		case "$$f" in \
			.config/gpg/gpg.conf|.config/gpg/gpg-agent.conf) continue ;; \
		esac; \
		p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
		if [ "$$p" = "644" ]; then \
			printf "✅ %s %s\n" "$$p" "$$f"; \
		else \
			printf "⚠️  %s %s (expected 644)\n" "$${p:-unknown}" "$$f"; \
		fi; \
	done; \
	find .config -type f -name "*.sh" -print0 | while IFS= read -r -d '' f; do \
		case "$$f" in \
			.config/gpg/gpg.conf|.config/gpg/gpg-agent.conf) continue ;; \
		esac; \
		p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
		if [ "$$p" = "644" ]; then \
			printf "✅ %s %s\n" "$$p" "$$f"; \
		else \
			printf "⚠️  %s %s (expected 644)\n" "$${p:-unknown}" "$$f"; \
		fi; \
	done; \
	find .config -type f -name "*.conf" -print0 | while IFS= read -r -d '' f; do \
		case "$$f" in \
			.config/gpg/gpg.conf|.config/gpg/gpg-agent.conf) continue ;; \
		esac; \
		p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
		if [ "$$p" = "644" ]; then \
			printf "✅ %s %s\n" "$$p" "$$f"; \
		else \
			printf "⚠️  %s %s (expected 644)\n" "$${p:-unknown}" "$$f"; \
		fi; \
	done; \
	echo ""; \
	echo "Sensitive config permissions (expect 600):"; \
	for f in .config/gpg/gpg.conf .config/gpg/gpg-agent.conf; do \
		[ -e "$$f" ] || continue; \
		p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
		if [ "$$p" = "600" ]; then \
			printf "✅ %s %s\n" "$$p" "$$f"; \
		else \
			printf "⚠️  %s %s (expected 600)\n" "$${p:-unknown}" "$$f"; \
		fi; \
	done; \
	echo ""; \
	echo "User security directories:"; \
	ssh_dir="$$HOME/.ssh"; \
	gnupg_dir="$$HOME/.gnupg"; \
	dotfiles_dir="$$HOME/.dotfiles"; \
	if [ -d "$$dotfiles_dir" ]; then \
		owner=$$(stat -c %U "$$dotfiles_dir" 2>/dev/null || stat -f %Su "$$dotfiles_dir" 2>/dev/null || echo unknown); \
		group_write=""; other_write=""; \
		perm=$$(eval "$$perm_of_cmd \"$$dotfiles_dir\"" 2>/dev/null || true); \
		case "$$perm" in \
			*?*?2|*?*?6) other_write="yes" ;; \
		esac; \
		case "$$perm" in \
			*2?*|*6?*) group_write="yes" ;; \
		esac; \
		if [ "$$owner" = "$$USER" ] && [ "$$group_write" != "yes" ] && [ "$$other_write" != "yes" ]; then \
			echo "✅ $$dotfiles_dir owned by $$USER and not group/world-writable"; \
		else \
			echo "⚠️  $$dotfiles_dir ownership/perms ($$owner, $$perm) should be owned by $$USER and not group/world-writable"; \
		fi; \
	else \
		echo "⚠️  $$dotfiles_dir missing"; \
	fi; \
	if [ -d "$$ssh_dir" ]; then \
		p=$$(eval "$$perm_of_cmd \"$$ssh_dir\"" 2>/dev/null || true); \
		if [ "$$p" = "700" ]; then \
			echo "✅ $$ssh_dir 700"; \
		else \
			echo "⚠️  $$ssh_dir $${p:-unknown} (expected 700)"; \
		fi; \
		for f in "$$ssh_dir"/config "$$ssh_dir"/config.local; do \
			[ -e "$$f" ] || continue; \
			if [ -L "$$f" ]; then \
				target=$$(readlink "$$f"); \
				case "$$target" in /*) ;; *) target="$$(cd "$$(dirname "$$f")" && echo "$$PWD/$$target")";; esac; \
				p=$$(eval "$$perm_of_cmd \"$$target\"" 2>/dev/null || true); \
				if [ "$$p" = "644" ] || [ "$$p" = "600" ]; then \
					echo "✅ $$f -> $$target $$p"; \
				else \
					echo "⚠️  $$f -> $$target $${p:-unknown} (expected 600 or 644)"; \
				fi; \
			else \
				p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
				if [ "$$p" = "600" ]; then \
					echo "✅ $$f 600"; \
				else \
					echo "⚠️  $$f $${p:-unknown} (expected 600)"; \
				fi; \
			fi; \
		done; \
		for f in "$$ssh_dir"/known_hosts "$$ssh_dir"/known_hosts*; do \
			[ -e "$$f" ] || continue; \
			p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
			if [ "$$p" = "644" ] || [ "$$p" = "600" ]; then \
				echo "✅ $$f $$p"; \
			else \
				echo "⚠️  $$f $${p:-unknown} (expected 600 or 644)"; \
			fi; \
		done; \
		for f in "$$ssh_dir"/*.pub; do \
			[ -e "$$f" ] || continue; \
			p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
			if [ "$$p" = "644" ] || [ "$$p" = "600" ]; then \
				echo "✅ $$f $$p"; \
			else \
				echo "⚠️  $$f $${p:-unknown} (expected 600 or 644)"; \
			fi; \
		done; \
		for f in "$$ssh_dir"/id_* "$$ssh_dir"/*_rsa "$$ssh_dir"/*_ed25519 "$$ssh_dir"/*_ecdsa; do \
			[ -e "$$f" ] || continue; \
			case "$$f" in *.pub) continue ;; esac; \
			p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
			if [ "$$p" = "600" ]; then \
				echo "✅ $$f 600"; \
			else \
				echo "⚠️  $$f $${p:-unknown} (expected 600)"; \
			fi; \
		done; \
	else \
		echo "⚠️  $$ssh_dir missing"; \
	fi; \
	if [ -d "$$gnupg_dir" ]; then \
		p=$$(eval "$$perm_of_cmd \"$$gnupg_dir\"" 2>/dev/null || true); \
		if [ "$$p" = "700" ]; then \
			echo "✅ $$gnupg_dir 700"; \
		else \
			echo "⚠️  $$gnupg_dir $${p:-unknown} (expected 700)"; \
		fi; \
		if [ -f "$$gnupg_dir/pubring.kbx" ]; then \
			p=$$(eval "$$perm_of_cmd \"$$gnupg_dir/pubring.kbx\"" 2>/dev/null || true); \
			if [ "$$p" = "644" ]; then \
				echo "✅ $$gnupg_dir/pubring.kbx 644"; \
			else \
				echo "⚠️  $$gnupg_dir/pubring.kbx $${p:-unknown} (expected 644)"; \
			fi; \
		fi; \
		find "$$gnupg_dir" -maxdepth 1 -type f | while IFS= read -r f; do \
			[ "$$f" = "$$gnupg_dir/pubring.kbx" ] && continue; \
			p=$$(eval "$$perm_of_cmd \"$$f\"" 2>/dev/null || true); \
			if [ "$$p" = "600" ]; then \
				echo "✅ $$f 600"; \
			else \
				echo "⚠️  $$f $${p:-unknown} (expected 600)"; \
			fi; \
		done; \
	else \
		echo "⚠️  $$gnupg_dir missing"; \
	fi

# Test configuration syntax
test:
	@echo "Testing configurations..."
	@zsh -n .zshrc && echo "✅ ZSH syntax OK" || echo "❌ ZSH syntax error"
	@git config --file .gitconfig --list > /dev/null && echo "✅ Git config OK" || echo "❌ Git config error"

# Shellcheck (lint shell scripts)
shellcheck:
	@echo "Running shellcheck..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "❌ shellcheck not found. Install with: sudo port install shellcheck"; exit 1; }
	@./scripts/shellcheck.sh

# shfmt (format shell scripts)
shfmt:
	@echo "Running shfmt..."
	@command -v shfmt >/dev/null 2>&1 || { echo "❌ shfmt not found. Install with: sudo port install shfmt"; exit 1; }
	@./scripts/shfmt.sh

# shfmt check (no changes)
shfmt-check:
	@echo "Running shfmt check..."
	@command -v shfmt >/dev/null 2>&1 || { echo "❌ shfmt not found. Install with: sudo port install shfmt"; exit 1; }
	@./scripts/shfmt.sh --check

# Format (alias)
fmt: shfmt

# Schedule cleanup (launchd/cron)
schedule-cleanup:
	@./scripts/install-cleanup-job.sh

# Unschedule cleanup
unschedule-cleanup:
	@./scripts/uninstall-cleanup-job.sh

# Lint (alias)
lint: shellcheck

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

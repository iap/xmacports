.PHONY: help bootstrap test test-zsh clean audit verify status shellcheck fmt-check python-lint test-secrets test-compliance sast ci-local ci-check secrets-init secrets-edit secrets-encrypt secrets-decrypt secrets-list

help:
	@echo "Dotfiles commands:"
	@echo "  make bootstrap     - link dotfiles into home"
	@echo "  make status        - show which tracked files are linked into \$$HOME"
	@echo "  make test          - run dotfiles test suite"
	@echo "  make test-zsh      - run zsh load-chain smoke test (catches zsh regressions)"
	@echo "  make verify        - run audit + verification scripts"
	@echo "  make shellcheck    - run shellcheck on shell scripts"
	@echo "  make fmt-check     - check shell formatting with shfmt"
	@echo "  make python-lint   - lint Python scripts with ruff"
	@echo "  make test-secrets  - run SOPS/age secret tests"
	@echo "  make test-compliance - run compliance checks"
	@echo "  make sast           - run static analysis / security checks"
	@echo "  make ci-local       - run GitLab CI pipeline locally via 'glab' or act"
	@echo "  make ci-check       - verify latest GitLab CI pipeline is green (reads GITLAB_TOKEN from env)"
	@echo "  make secrets-init   - generate the age key and initialise the secret store"
	@echo "  make secrets-edit   - open the encrypted secrets in \$$EDITOR (via sops)"
	@echo "  make secrets-encrypt - re-encrypt secrets/secrets.yaml -> secrets.enc.yaml"
	@echo "  make secrets-decrypt - decrypt secrets.enc.yaml -> secrets/secrets.yaml"
	@echo "  make secrets-list   - list secret keys in the default namespace"

bootstrap:
	bash bootstrap.sh

test:
	bash tests/run-tests.sh

# zsh regression lane: the dotfiles load chain is sourced under zsh too (.zshrc
# -> shared/*.sh), but tests/run-tests.sh is a bash runner. Run the dedicated
# zsh smoke test so a zsh-path regression can't ship green.
test-zsh:
	@if ! command -v zsh >/dev/null 2>&1; then \
		echo "zsh not found; install via: mise install or your package manager"; \
		echo "Skipping test-zsh"; \
	else \
		zsh tests/test-zsh.zsh && echo "test-zsh passed"; \
	fi

clean:
	rm -rf "$$HOME/.dotfiles-backup-"*

audit:
	bash scripts/audit.sh

verify:
	bash scripts/verify-migration.sh
	bash tests/verify-dotfiles.sh
	bash scripts/audit.sh

shellcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		if [ -n "$${CI:-}" ]; then \
			echo "ERROR: shellcheck not installed but CI=$${CI} is set - failing hard"; \
			exit 1; \
		fi; \
		echo "shellcheck not found; install via: mise install"; \
		echo "Skipping shellcheck"; \
	else \
		bash scripts/shellcheck.sh && echo "shellcheck passed"; \
	fi

fmt-check:
	@if ! command -v shfmt >/dev/null 2>&1; then \
		if [ -n "$${CI:-}" ]; then \
			echo "ERROR: shfmt not installed but CI=$${CI} is set - failing hard"; \
			exit 1; \
		fi; \
		echo "shfmt not found; install via: mise install"; \
		echo "Skipping fmt-check"; \
	else \
		bash scripts/shfmt.sh --check && echo "fmt-check passed"; \
	fi

python-lint:
	@if command -v ruff >/dev/null 2>&1; then \
		ruff check scripts/ && echo "python-lint passed"; \
	elif command -v uv >/dev/null 2>&1; then \
		uv tool run ruff check scripts/ && echo "python-lint passed"; \
	elif [ -n "$${CI:-}" ]; then \
		echo "ERROR: ruff/uv not found but CI=$${CI} is set - failing hard"; \
		exit 1; \
	else \
		echo "ruff/uv not found; install from https://astral.sh/uv"; \
		echo "Skipping python-lint"; \
	fi

test-secrets:
	bash tests/test-secrets.sh

# Secret store management. The implementations live in shared/secrets.sh as
# shell functions, so each target sources platform.sh (for DOTFILES_ROOT and
# log_* helpers) then secrets.sh before invoking one.
SECRETS_SH = set -e; \
	export DOTFILES_ROOT="$(CURDIR)"; \
	. "$(CURDIR)/shared/platform.sh"; \
	. "$(CURDIR)/shared/functions.sh"; \
	. "$(CURDIR)/shared/secrets.sh";

secrets-init:
	bash scripts/secrets-init.sh

secrets-edit:
	@bash -c '$(SECRETS_SH) secrets_edit'

secrets-encrypt:
	@bash -c '$(SECRETS_SH) secrets_encrypt'

secrets-decrypt:
	@bash -c '$(SECRETS_SH) secrets_decrypt'

secrets-list:
	@bash -c '$(SECRETS_SH) secret_list "$(NS)"'

# Show which tracked dotfiles are currently linked into $HOME.
status:
	@bash -c 'cd "$(CURDIR)"; \
	for t in .profile .bash_profile .bashrc .zprofile .zshrc .gitconfig \
	         .gitignore_global .forward .vimrc; do \
	  p="$$HOME/$$t"; \
	  if [ -L "$$p" ]; then \
	    printf "linked    %-22s -> %s\n" "~/$$t" "$$(readlink "$$p")"; \
	  elif [ -e "$$p" ]; then \
	    printf "REAL FILE %-22s (not linked)\n" "~/$$t"; \
	  else \
	    printf "missing   %-22s\n" "~/$$t"; \
	  fi; \
	done'

test-compliance:
	DOTFILES_ROOT="$(CURDIR)" bash tests/run-tests.sh compliance

sast: shellcheck fmt-check
	@if command -v ruff >/dev/null 2>&1 || command -v uv >/dev/null 2>&1; then \
		$(MAKE) python-lint; \
	elif [ -n "$${CI:-}" ]; then \
		echo "ERROR: ruff/uv not found but CI=$${CI} is set - failing hard"; \
		exit 1; \
	else \
		echo "ruff/uv not found; skipping python-lint"; \
	fi

# Run the GitLab CI pipeline locally using 'glab' or 'act' (GitHub Actions runner).
# Requires: glab CLI authenticated OR act + Docker daemon.
# The pipeline is defined in .ci/gitlab-ci.yml (included by .gitlab-ci.yml).
ci-local:
	@if command -v act >/dev/null 2>&1; then \
		act --rm --workflows .gitlab-ci.yml --env DOTFILES_ROOT=/workspaces/$(CURDIR); \
	elif command -v glab >/dev/null 2>&1; then \
		echo "NOTE: glab doesn't run pipelines locally. Use 'act' or push to trigger."; \
		echo "Install act: https://github.com/nektos/act"; \
		exit 1; \
	else \
		echo "Neither act nor glab found. Install act for local pipeline runs:"; \
		echo "  https://github.com/nektos/act"; \
		exit 1; \
	fi

# Verify the latest GitLab CI pipeline for the authoritative repo is green.
# GitLab CI reports status natively to GitLab's commit/MR UI, so it is the
# authoritative source. Credentials: GITLAB_TOKEN env var (or glab auth).
ci-check:
	@if ! command -v glab >/dev/null 2>&1 && [ -z "${GITLAB_TOKEN:-}" ]; then \
		echo "ERROR: neither glab CLI nor GITLAB_TOKEN found."; \
		echo "Fix: install glab (https://gitlab.com/gitlab-org/cli) or set GITLAB_TOKEN."; \
		exit 1; \
	fi
	DOTFILES_ROOT="$(CURDIR)" bash .ci/scripts/gitlab-ci-verify.sh

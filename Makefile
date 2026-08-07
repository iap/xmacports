.PHONY: help bootstrap test clean audit verify shellcheck fmt-check python-lint test-secrets test-compliance sast ci-local

help:
	@echo "Dotfiles commands:"
	@echo "  make bootstrap     - link dotfiles into home"
	@echo "  make test          - run dotfiles test suite"
	@echo "  make verify        - run audit + verification scripts"
	@echo "  make shellcheck    - run shellcheck on shell scripts"
	@echo "  make fmt-check     - check shell formatting with shfmt"
	@echo "  make python-lint   - lint Python scripts with ruff"
	@echo "  make test-secrets  - run SOPS/age secret tests"
	@echo "  make test-compliance - run compliance checks"
	@echo "  make sast           - run static analysis / security checks"
	@echo "  make ci-local       - run .drone.yml locally via 'drone exec' (needs Docker daemon)"

bootstrap:
	bash bootstrap.sh

ifeq ($(wildcard tests/run-tests.sh),tests/run-tests.sh)
test:
	bash tests/run-tests.sh
else
test:
	bash tests/test-bootstrap.sh
	bash tests/verify-dotfiles.sh
	@bash -n bootstrap.sh
endif

clean:
	rm -rf "$$HOME/.dotfiles-backup-"*

audit:
	bash scripts/audit.sh

verify:
	bash scripts/verify-migration.sh
	bash scripts/audit.sh

shellcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not found; install via: mise install"; \
		echo "Skipping shellcheck in CI"; \
	else \
		bash scripts/shellcheck.sh && echo "shellcheck passed"; \
	fi

fmt-check:
	@if ! command -v shfmt >/dev/null 2>&1; then \
		echo "shfmt not found; install via: mise install"; \
		echo "Skipping fmt-check in CI"; \
	else \
		bash scripts/shfmt.sh --check && echo "fmt-check passed"; \
	fi

python-lint:
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "uv not found; install from https://astral.sh/uv"; \
		echo "Skipping python-lint in CI"; \
	else \
		uv tool run ruff check scripts/; \
	fi

test-secrets:
	bash tests/test-secrets.sh

test-compliance:
	DOTFILES_ROOT="$(CURDIR)" bash tests/run-tests.sh compliance

sast: shellcheck fmt-check
	@if command -v uv >/dev/null 2>&1; then \
		make python-lint; \
	else \
		echo "uv not found; skipping python-lint in CI"; \
	fi

# Run the real .drone.yml pipeline locally via the Drone CLI, so the local run
# can never drift from CI. Requires the Docker daemon (Docker Desktop / Podman
# socket). No server token needed — drone exec is fully local.
ci-local:
	@if ! command -v drone >/dev/null 2>&1; then \
		echo "drone CLI not found. Install: download drone_darwin_$(uname -m) from"; \
		echo "https://github.com/harness/drone-cli/releases/latest into ~/bin"; \
		exit 1; \
	fi
	DOTFILES_ROOT="$(CURDIR)" drone exec --trusted

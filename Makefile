.PHONY: help bootstrap test clean audit verify shellcheck fmt-check python-lint test-secrets test-compliance

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

bootstrap:
	bash bootstrap.sh

ifeq ($(wildcard tests/run-tests.sh),tests/run-tests.sh)
test:
	bash tests/run-tests.sh
else
test:
	bash tests/test-bootstrap.sh
	bash tests/verify-dotfiles.sh
	@bash -n bootstrap.sh || true
endif

clean:
	rm -rf "$HOME/.dotfiles-backup-"*

audit:
	bash scripts/audit.sh

verify:
	bash scripts/verify-migration.sh
	bash scripts/audit.sh

shellcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not found; install via: mise install"; \
		exit 1; \
	fi
	bash scripts/shellcheck.sh

fmt-check:
	@if ! command -v shfmt >/dev/null 2>&1; then \
		echo "shfmt not found; install via: mise install"; \
		exit 1; \
	fi
	bash scripts/shfmt.sh --check

python-lint:
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "uv not found; install from https://astral.sh/uv"; \
		exit 1; \
	fi
	uv tool run ruff check scripts/

test-secrets:
	bash tests/test-secrets.sh

test-compliance:
	DOTFILES_ROOT="$(CURDIR)" bash tests/run-tests.sh compliance

.PHONY: help bootstrap test clean audit verify

help:
	@echo "Dotfiles commands:"
	@echo "  make bootstrap   - link dotfiles into home"
	@echo "  make test        - run dotfiles test suite"
	@echo "  make clean       - remove backup dirs"
	@echo "  make audit       - check dotfiles health"
	@echo "  make verify      - run audit + verification scripts"

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

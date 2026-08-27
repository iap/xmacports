# Contributing

Thanks for contributing to these dotfiles.

## Prerequisites

- `mise` for project tooling and runtimes
- Git with GPG signing configured
- GPG key `9166D30F6FE70F56` registered locally

## Setup

```bash
git clone git@gitlab.com:iap/xmacports.git ~/.dotfiles
cd ~/.dotfiles
make bootstrap
mise install
```

## Toolchain

- Shell lint/format: `shellcheck`, `shfmt` via `mise`
- Secrets: `age`, `sops` via `mise`
- Python lint: `ruff` via `uv`

## Commits

- All commits should be GPG-signed.
- If pinentry blocks signing in a non-interactive shell, use a terminal with agent access or ask before switching signing methods.

## Secrets

- Encrypted store: `secrets/secrets.enc.yaml`
- Decrypt on demand with `secret()`, `with_secret()`, or `secrets_decrypt()`
- Never commit plaintext secrets or age keys

## Tests

```bash
make test
make verify
```

## Lint

```bash
make shellcheck
make fmt-check
make python-lint
make test-compliance
```

## CI

- Primary CI: Drone

## Merge policy

- The project uses **fast-forward** merges only. Rebase your branch onto the
  authoritative remote before merging (see MANUAL.md for the full workflow).
- Never force-push `main`.

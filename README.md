# Dotfiles

> Cross-platform home directory configuration with deterministic shell startup, file-based bootstrap, and no package-manager automation.

## What This Repo Does

- Links shell, Git, SSH, GPG, and editor configuration into `$HOME`
- Keeps shared environment logic in one place for bash and zsh
- Provides small helper scripts for inspection, cleanup, and verification
- Supports optional local override files and an optional private overlay

## Quick Start

```bash
git clone <repository-url> "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
make test
```

Install required tools manually before bootstrapping:

- `bash`
- `zsh`
- `git`
- `gpg` and `gpgconf`
- `pinentry` of your choice
- `shellcheck`
- `shfmt`

## Layout

- `.profile` - POSIX shared base for login shells
- `.bash_profile` - bash login entrypoint
- `.bashrc` - bash interactive entrypoint
- `.zprofile` - zsh login entrypoint
- `.zshrc` - zsh interactive entrypoint
- `.config/env.d/platform.sh` - shared environment loader
- `.config/env.d/foundry.sh` - optional Foundry wrapper functions
- `shared/` - cross-shell functions and aliases
- `bin/` - small executable helpers
- `scripts/` - maintenance and verification helpers
- `templates/` and `examples/` - starter configs for local overrides

## Bootstrap

`make bootstrap` is idempotent. It links tracked files into `$HOME`, backs up replaced targets once, and applies the minimal permissions required for GPG and SSH config.

It does not install system packages.

## Local Overrides

Use local override files for machine-specific or private settings:

```bash
cp templates/profile-local.example    "$HOME/.profile.local"
cp examples/gitconfig-local-example   "$HOME/.gitconfig.local"
cp examples/forward-local-example     "$HOME/.forward.local"
cp examples/zshrc-local-example       "$HOME/.zshrc.local"
```

## Maintenance

- `make status` - show linked files
- `make test` - syntax checks for startup files
- `make check` - run shfmt and shellcheck
- `make audit` - inspect permissions
- `make test-all` - run the full test wrapper

## Security

- Secrets are not exported from shell startup
- `umask 077` keeps new files private by default
- GPG and SSH config files are permission-checked
- Local/private overlays stay outside the tracked repo

## Documentation

- `MANUAL.md` - detailed startup order, architecture, and troubleshooting
- `AGENTS.md` - repo operating rules for agentic edits

# Dotfiles

> Cross-platform home directory configuration with deterministic shell startup, file-based bootstrap, and no package-manager automation.

**Authoritative remote:** [GitLab](https://gitlab.com/iap/xmacports.git) | **Mirror:** [GitHub](https://github.com/iap/xmacports)

## What This Repo Does

- Links shell, Git, SSH, GPG, and editor configuration into `$HOME`
- Keeps shared environment logic in one place for bash and zsh
- Provides small helper scripts for inspection, cleanup, and verification
- Supports optional local override files and an optional private overlay

## Quick Start

```bash
git clone git@gitlab.com:iap/xmacports.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
make test
```

## Prerequisites

- `bash`, `zsh`, `git`, `gpg`, `gpgconf`, `pinentry`
- `make`, `mise`, `age`, `sops`
- `shellcheck`, `shfmt` (for SAST)

## Layout

- `.profile` - POSIX shared base for login shells
- `.bash_profile` - bash login entrypoint
- `.bashrc` - bash interactive entrypoint
- `.zprofile` - zsh login entrypoint
- `.zshrc` - zsh interactive entrypoint
- `shared/platform.sh` - shared environment loader
- `.config/env.d/` - optional environment modules (proxy, foundry, user-local-bin)
- `.config/gpg/gpg.conf` - GnuPG configuration
- `.config/gpg/gpg-agent.conf` - GnuPG agent configuration
- `.config/ssh/config` - SSH configuration
- `.config/vim/vimrc` - XDG vim runtime config
- `.config/vim/privacy.vim` - vim privacy settings
- `.config/npm/config` - npm privacy configuration
- `shared/` - cross-shell functions and aliases
- `bin/` - small executable helpers
- `scripts/` - maintenance and verification helpers
- `templates/` and `examples/` - starter configs for local overrides
- `secrets/` - SOPS + age encrypted secret store

## Bootstrap

`make bootstrap` is idempotent. It links tracked files into `$HOME`, backs up replaced targets once, and applies the minimal permissions required for GPG and SSH config.

It does not install system packages.

## Local Overrides

Use local override files for machine-specific or private settings. Templates are available in `templates/` and additional examples in `examples/`:

```bash
# Required for most users
cp templates/profile-local.example    "$HOME/.profile.local"

# Optional overrides (copy from examples/)
cp examples/gitconfig-local-example   "$HOME/.gitconfig.local"
cp examples/forward-local-example     "$HOME/.forward.local"
cp examples/zshrc-local-example       "$HOME/.zshrc.local"
```

## Opt-in app configs

Two app configs are tracked but **opt-in** via env flags. Bootstrap backs up
any replaced files before linking and links no secret-bearing files:

```bash
DOTFILES_ENABLE_FISH=1 make bootstrap   # links .config/fish/conf.d/* into ~/.config/fish/conf.d
DOTFILES_ENABLE_GH=1    make bootstrap   # links .config/gh/config.yml into ~/.config/gh
```

- **fish**: links tracked `conf.d/*` files only.
- **gh**: links only `config.yml` (preferences). `hosts.yml` holds OAuth tokens
  and is intentionally never tracked or linked — your tokens stay local.

## Security

- Secrets are not exported from shell startup; use `secret()` or `with_secret()` for on-demand access
- GPG and SSH config files are permission-checked
- Local/private overlays stay outside the tracked repo
- Sensitive values are encrypted with age via SOPS and committed as `secrets/secrets.enc.yaml`
- Pre-commit hook blocks plaintext secret files and validates SOPS encryption

## Documentation

- `MANUAL.md` - detailed startup order, architecture, and troubleshooting
- `CONTRIBUTING.md` - how to contribute (branch naming, commit format, MR workflow)
- `AGENTS.md` - repo operating rules for agentic edits

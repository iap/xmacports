# Dotfiles

> Cross-platform home directory configuration with deterministic shell startup, file-based bootstrap, and no package-manager automation.

**[GitHub](https://github.com/iap/xmacports) | [GitLab](https://gitlab.com/iap/xmacports)**

> [!IMPORTANT]
> Clone this repo into `$HOME/.dotfiles` exactly. Bootstrap and startup files assume that path — following the repo directory name (e.g. `xmacports`, `dotfiles`) will break linking and shell startup.

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
This is verified: cloning into any other directory name leaves the shell environment unconfigured.

### Install required tools manually before bootstrapping:

- `bash`
- `zsh`
- `git`
- `gpg` and `gpgconf`
- `pinentry` of your choice
- `mise` — the only allowed tool/runtime manager ([install](https://mise.jdx.dev/install.html)); run `mise install` after cloning to fetch shellcheck, shfmt, ruff, and runtime pins from `.mise.toml`
- `shellcheck`
- `shfmt`
- `sops` and `age` _(for encrypted secret management)_
- `glab` _(optional — GitLab CLI for repo/mirror management; [install](https://gitlab.com/gitlab-org/cli#installation))_
- `gh` _(optional — GitHub CLI for repo/release management; [install](https://cli.github.com/))_

## Layout

- `.profile` - POSIX shared base for login shells
- `.bash_profile` - bash login entrypoint
- `.bashrc` - bash interactive entrypoint
- `.zprofile` - zsh login entrypoint
- `.zshrc` - zsh interactive entrypoint
- `.config/env.d/platform.sh` - shared environment loader
- `.config/env.d/foundry.sh` - Foundry wrappers (opt-in via `~/.profile.local`)
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

## Maintenance

- `make status` - show linked files
- `make test` - syntax checks for startup files
- `make check` - run shfmt and shellcheck
- `make audit` - inspect permissions
- `make test-all` - run the full test wrapper
- `make secrets-init` - bootstrap age keypair and SOPS config
- `make secrets-encrypt` - encrypt plaintext secrets
- `make secrets-edit` - open encrypted secrets in editor

## Security

- Secrets are not exported from shell startup; use `secret()` or `with_secret()` for on-demand access
- `umask 077` keeps new files private by default
- GPG and SSH config files are permission-checked
- Local/private overlays stay outside the tracked repo
- Sensitive values are encrypted with age via SOPS and committed as `secrets/secrets.enc.yaml`
- Pre-commit hook blocks plaintext secret files and validates SOPS encryption

## Signed Merges

`main` is protected (no direct push; merge = Maintainers; no force-push) and every
commit must be GPG-signed by the personal key. Merge feature branches **locally**
with the `smerge` alias instead of GitLab's merge button, so the resulting merge
commit is authored by and signed with the personal key (the GitLab UI would stamp
its noreply identity + GitLab's key):

    git smerge <feature-branch>        # --no-ff -S merge into main, then push

The alias lives in `.gitconfig` (after the dotfiles are linked to `~/.gitconfig`).
Rebased/rewritten branches are re-signed during the rebase, so history stays
consistently signed.

## Documentation

- `MANUAL.md` - detailed startup order, architecture, and troubleshooting
- `AGENTS.md` - repo operating rules for agentic edits

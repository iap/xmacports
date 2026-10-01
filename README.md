# Dotfiles

> Cross-platform home directory configuration with deterministic shell startup, file-based bootstrap, and no package-manager automation.

**Authoritative remote:** [GitLab](https://gitlab.com/iap/xmacports.git) | **Mirror:** [GitHub](https://github.com/iap/xmacports)

> [!NOTE]
> Naming: the forge repo is called `xmacports` for history; the canonical
> checkout path is `~/.dotfiles`. Never rename either to match the other.
> Code must use `DOTFILES_ROOT`, never a hardcoded `~/xmacports`.

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
- `uv` (provides `ruff` for python-lint via `uv tool run ruff`)

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
- `scripts/install-git-source.sh` - manual, pinned git source build (no sudo)
- `templates/` and `examples/` - starter configs for local overrides
- `secrets/` - SOPS + age encrypted secret store
- `tests/` - behavior checks; `.githooks/` - commit/push guards; `.ci/` - GitLab pipeline

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
DOTFILES_ENABLE_FISH=1 make bootstrap   # planned: no fish files tracked yet, flag accepted but links nothing
DOTFILES_ENABLE_GH=1    make bootstrap   # links .config/gh/config.yml into ~/.config/gh
```

- **fish**: planned opt-in; no `conf.d/*` files are tracked yet, so the flag
  currently links nothing.
- **gh**: links only `config.yml` (preferences). `hosts.yml` holds OAuth tokens
  and is intentionally never tracked or linked — your tokens stay local.

## Security

- Secrets are not exported from shell startup; use `secret()` or `with_secret()` for on-demand access
- GPG and SSH config files are permission-checked
- Local/private overlays stay outside the tracked repo
- Sensitive values are encrypted with age via SOPS and committed as `secrets/secrets.enc.yaml`
- The store is encrypted to two age recipients — the primary machine key and an offline recovery key — so losing either single key leaves the store readable (recipients listed in `.sops.yaml`)
- Pre-commit hook blocks plaintext secret files and validates SOPS encryption

## Git source build

Some tools require a git newer than the one macOS ships — the Graphite CLI needs
`2.38.0` or newer, and the system git on this host is `2.37.1`. When MacPorts is
not an option (it needs sudo, and its support matrix does not cover every macOS
release), `scripts/install-git-source.sh` builds a pinned git from the official
tarball into `~/.local` — no sudo, no system directories touched.

This is a **manual, operator-run step**. It is deliberately not wired into
`make bootstrap` or any shell startup file, per the "No Package Manager
Automation" rule in `AGENTS.md`.

```bash
scripts/install-git-source.sh --check     # report current state, change nothing
scripts/install-git-source.sh             # download, verify, build, install
scripts/install-git-source.sh --dry-run   # build but do not install
```

- The version and its SHA256 are pinned at the top of the script. The checksum is
  verified against that pin, then corroborated against upstream's published
  manifest; a mismatch is always fatal. The pin is the trust anchor — the
  manifest fetch is corroboration, not independent proof, because its PGP
  signature is not verified here.
- System and package-managed prefixes (`/usr`, `/opt/homebrew`, `/opt/local`, …)
  are refused outright: the installer replaces `bin/git` and `libexec/git-core`.
- The build refuses to run below the `2.38.0` floor.
- An upgrade moves the old `bin/git` and `libexec/git-core` aside and restores them
  if `make install` fails, so a failed upgrade never leaves the prefix without a
  working git.
- After installing, open a new login shell (or `hash -r`) so `PATH` resolves the
  new binary. `shared/platform.sh` already orders `~/.local/bin` ahead of
  `/usr/local/bin` and `/usr/bin`.
- The build refuses to run below the `2.38.0` floor.
- `make install` overlays git's helpers, so the script removes the previous
  `bin/git` and `libexec/git-core` first to avoid mixing old and new files.
- After installing, open a new login shell (or `hash -r`) so `PATH` resolves the
  new binary. `shared/platform.sh` already orders `~/.local/bin` ahead of
  `/usr/local/bin` and `/usr/bin`.

To change the pinned version, edit `GIT_VERSION` and `GIT_SHA256` at the top of the
script and re-run it. Re-derive the checksum from
<https://mirrors.edge.kernel.org/pub/software/scm/git/sha256sums.asc>.

## Documentation

- `MANUAL.md` - detailed startup order, architecture, and troubleshooting
- `CONTRIBUTING.md` - how to contribute (branch naming, commit format, MR workflow)
- `AGENTS.md` - repo operating rules for agentic edits

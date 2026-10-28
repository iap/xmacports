# Architecture

This document describes the system architecture, component relationships, and
load chains for the xmacports dotfiles repository.

## Overview

The dotfiles repository is a **layered configuration system** that links tracked
files into `$HOME` and provides a shared environment across bash and zsh on
macOS and Linux.

```text
┌─────────────────────────────────────────────────────┐
│                    User's $HOME                     │
│  (symlinks to ~/.dotfiles tracked files)            │
├─────────────────────────────────────────────────────┤
│  Shell entry points                                 │
│  .bash_profile  .zprofile  .profile                 │
│  .bashrc  .zshrc                                    │
├─────────────────────────────────────────────────────┤
│  Shared interactive layer                           │
│  shared/platform.sh → shared/functions.sh           │
│  → shared/secrets.sh → shared/aliases.sh            │
├─────────────────────────────────────────────────────┤
│  Optional env modules                               │
│  .config/env.d/*.sh                                 │
├─────────────────────────────────────────────────────┤
│  Private overlays (untracked)                       │
│  ~/.gitconfig.local  ~/.profile.local               │
│  ~/.zshrc.local  ~/.ssh/allowed_signers             │
└─────────────────────────────────────────────────────┘
```

## Shell load chains

### bash (login shell)

```text
~/.bash_profile
  └── ~/.profile          (POSIX shared base)
        └── ~/.bashrc     (interactive)
              └── shared/platform.sh
                    └── shared/functions.sh
                          └── shared/secrets.sh
                    └── shared/aliases.sh
              └── .config/env.d/*.sh (optional)
```

### zsh (login shell)

```text
~/.zprofile
  └── ~/.profile          (POSIX shared base)
        └── ~/.zshrc      (interactive)
              └── shared/platform.sh
                    └── shared/functions.sh
                          └── shared/secrets.sh
                    └── shared/aliases.sh
              └── .zshrc.d/prompt.sh (zsh-only prompt)
              └── .config/env.d/*.sh (optional)
```

### Key invariants

- `.profile` is POSIX and sourced by both bash and zsh.
- `shared/platform.sh` has a load guard (`DOTFILES_PLATFORM_LOADED`) to prevent
  double-sourcing.
- `shared/functions.sh` sources `platform.sh` and `secrets.sh` if not already
  loaded.
- No top-level `set -u` in sourced files — they must be safe under a caller's
  `set -u`.
- All variable reads use `${VAR:-}` defaults.

## Component ownership

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| `bootstrap.sh` | Setup | Symlinks tracked files, applies permissions, creates dirs |
| `shared/platform.sh` | Environment | XDG defaults, PATH assembly, platform detection, GPG agent |
| `shared/functions.sh` | Utilities | Cross-shell functions (mkcd, log_info, git helpers, etc.) |
| `shared/aliases.sh` | Aliases | Cross-shell aliases and secret hygiene |
| `shared/secrets.sh` | Secrets | On-demand secret access via `secret()`, `with_secret()` |
| `shared/prompt.sh` | Prompt | Cross-shell prompt core (color-free) |
| `.zshrc.d/prompt.sh` | Prompt | Zsh-specific prompt renderer |
| `scripts/` | Maintenance | Verification, audit, CI, secret management |
| `.githooks/` | Git safety | pre-commit (secrets), commit-msg (attribution), pre-push (branch guard) |
| `.ci/` | CI/CD | GitLab pipeline definition and verification scripts |
| `secrets/` | Secrets | SOPS + age encrypted store |
| `keys/` | Signing | GPG public key export, SSH allowed signers |
| `tests/` | Testing | Syntax and behavior checks |
| `examples/` | Reference | Copy-paste snippets for local overrides |
| `templates/` | Starting points | Template files for local overrides |

## Data flow

### Secrets

```text
secrets/secrets.yaml (plaintext, gitignored)
  → make secrets-encrypt
  → secrets/secrets.enc.yaml (encrypted, tracked)
  → make secrets-decrypt (on another machine)
  → secrets/secrets.yaml (plaintext, gitignored)
```

Access at runtime: `secret "namespace" "key"` → reads from decrypted store.

### Platform detection

```text
shared/platform.sh
  ├── is_macos() / is_linux() — uname-based
  ├── has_cmd() — command -v wrapper
  ├── PATH assembly — ~/.local/bin, ~/.dotfiles/bin, mise shims
  ├── XDG defaults — XDG_CONFIG_HOME, XDG_DATA_HOME, etc.
  └── GPG agent discovery — SSH_AUTH_SOCK, GPG_TTY
```

### Signing

```text
Git commit
  → gpg.format = ssh (from ~/.gitconfig.local)
  → user.signingkey = ~/.ssh/id_ed25519 (NEW_G2wL)
  → SSH signature with namespaces="git"
  → verified against keys/allowed_signers (tracked, reads from origin/main)
  → CI: scripts/check-signatures.sh verifies %G? = G
```

## File linking (bootstrap)

`bootstrap.sh` creates symlinks from tracked files to `$HOME`:

```text
~/.profile          → ~/.dotfiles/.profile
~/.bash_profile     → ~/.dotfiles/.bash_profile
~/.bashrc           → ~/.dotfiles/.bashrc
~/.zprofile         → ~/.dotfiles/.zprofile
~/.zshrc            → ~/.dotfiles/.zshrc
~/.gitconfig        → ~/.dotfiles/.gitconfig
~/.gitignore_global → ~/.dotfiles/.gitignore_global
~/.config/...       → ~/.dotfiles/.config/...
```

Backups are created in `~/.dotfiles-backup-<timestamp>/` before overwriting.

## Testing

```text
tests/run-tests.sh          # bash test runner (bats-style)
tests/test-zsh.zsh          # zsh load-chain smoke test
tests/verify-dotfiles.sh    # structural verification
scripts/audit.sh            # permission and compliance
```

CI runs all of the above plus shellcheck, shfmt, python-lint, and custom gates
(signature-check, attribution-check, merge-gates).

## Cross-platform notes

- **macOS:** bash 3.2, `stat -f`, `sysctl`, MacPorts for system packages
- **Linux:** bash 4+, `stat -c`, `/proc/cpuinfo`, `nproc`
- **Windows/WSL:** nixos distro, Linux paths, edited from Windows host
- Shared files use `[[ ]]` (bash/zsh compatible) and `${VAR:-}` defaults
- OS-specific code is gated behind `is_macos()` / `is_linux()`

## Security boundaries

- **Tracked (public):** all files in git, treated as world-readable
- **Untracked (private):** `~/.dotfiles-private/` (keybase-encrypted), `~/.gitconfig.local`,
  `~/.profile.local`, `~/.zshrc.local`, `secrets/secrets.yaml`
- **Gitignored:** `reviews/`, `docs/gpg-ssh-*.md`, `secrets/secrets.yaml`,
  `.cache/`, `.kilo/`, tool caches
- **Encrypted:** `secrets/secrets.enc.yaml` (SOPS + age, tracked)

## Related documents

- [README.md](../README.md) — user-facing documentation
- [CONTRIBUTING.md](../CONTRIBUTING.md) — single source of truth
- [AGENTS.md](../AGENTS.md) — critical operating rules
- [CLAUDE.md](../CLAUDE.md) — Claude Code context
- [docs/style-guide.md](style-guide.md) — documentation formatting

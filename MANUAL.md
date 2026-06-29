# Dotfiles Manual

## Architecture

This repo is organized around a small number of clear responsibilities:

- `bootstrap.sh` links files into `$HOME` and applies permissions
- `.profile` provides the POSIX shared base for all login shells
- `.bash_profile` and `.zprofile` load `.profile`
- `.bashrc` and `.zshrc` load the shared interactive environment
- `.config/env.d/platform.sh` holds shared environment defaults
- `.config/env.d/foundry.sh` provides optional Ethereum development wrappers
- `shared/functions.sh` and `shared/aliases.sh` expose cross-shell helpers
- `.zshrc.d/prompt.sh` provides zsh-specific prompt formatting
- `bin/` contains small user-facing helper executables
- `scripts/` contains verification, maintenance, and cleanup helpers

The repo does not automate package installation. It assumes required tools are installed manually.

`mise` is supported as an optional per-user developer tool manager for language runtimes and shims, but it is not part of bootstrap or system provisioning.

## Shell Load Order

### bash login shell

```text
/etc/profile -> ~/.profile -> ~/.bash_profile -> ~/.bashrc
```

`.profile.local` is sourced by `.bashrc` after `platform.sh` loads, so user PATH
additions take precedence over system directories.

### zsh login shell

```text
~/.profile -> ~/.zprofile -> ~/.zshrc
```

`.profile.local` is sourced by `.zshrc` after `platform.sh` loads (via `.zshrc.d/env.sh`),
so user PATH additions take precedence over system directories.

### Shared interactive layer

Both shells load shared configuration:

```text
# .bashrc loads directly:
.config/env.d/platform.sh
.config/env.d/foundry.sh
shared/functions.sh
shared/aliases.sh
~/.profile.local (after platform.sh, with double-sourcing guard)

# .zshrc loads via .zshrc.d/env.sh:
.zshrc.d/env.sh       -> .config/env.d/platform.sh
.config/env.d/foundry.sh
shared/functions.sh
shared/aliases.sh
.zshrc.d/prompt.sh
~/.profile.local (after platform.sh, with double-sourcing guard)
```

Both shells now consistently load foundry.sh if available. `.zshrc.d/env.sh` provides intermediate loading with duplicate protection for platform.sh.

`.profile.local` is loaded exactly once per shell session, after `platform.sh` assembles PATH.

## Environment Rules

`platform.sh` is the central environment loader. It is responsible for:

- XDG directory defaults
- PATH assembly
- GPG agent socket discovery
- `GPG_TTY` setup
- optional Foundry path discovery
- default editor and locale values
- privacy-oriented telemetry defaults
- optional `mise`-driven shim activation when `mise` is already installed

It must remain safe to source more than once and safe under `set -u`.

## File Tree

```text
$HOME/.dotfiles/
├── .bash_profile
├── .bashrc
├── .profile
├── .zprofile
├── .zshrc
├── .forward
├── .zshrc.d/
│   ├── env.sh
│   └── prompt.sh
├── .config/
│   ├── env.d/
│   │   ├── platform.sh
│   │   └── foundry.sh
│   ├── gpg/
│   │   ├── gpg.conf
│   │   └── gpg-agent.conf
│   ├── ssh/
│   │   └── config
│   ├── vim/
│   │   ├── vimrc
│   │   └── privacy.vim
│   └── npm/
│       └── config
├── shared/
│   ├── functions.sh
│   └── aliases.sh
├── bin/
│   ├── pinentry-fallback
│   ├── system-info
│   └── update
├── scripts/
│   ├── compliance-check.sh
│   └── cleanup-*.sh
├── templates/
│   ├── profile-local.example
│   └── server-profile.example
└── examples/
    ├── gitconfig-local-example
    ├── forward-local-example
    ├── zshrc-local-example
    ├── vimrc-local-example
    └── ssh-config-example
```

## Bootstrap Behavior

`make bootstrap` and `./bootstrap.sh` are linkers, not installers.

The bootstrap flow:

1. Back up any existing target file once
2. Symlink the repo file into place
3. Create `~/.gnupg` and `~/.ssh` with restrictive permissions
4. Set `core.hooksPath` if `.githooks/` exists
5. Print reminders for optional local override files

The bootstrap must stay idempotent. Running it twice should not duplicate backups or corrupt existing links.

## Optional Private Overlay

If you maintain private shell config in a separate repository, keep it outside the tracked repo and treat it as optional. Do not make core startup depend on it.

Recommended overlay files:

- `~/.bashrc.local`
- `~/.zshrc.local`
- `~/.profile.local`
- `~/.gitconfig.local`
- `~/.forward.local`
- `~/.ssh/config.local`

## Maintenance Rules

- Keep shell files small and focused
- Prefer explicit path checks over hidden side effects
- Avoid package-manager automation or install wrappers
- Keep docs and tests aligned with the actual file layout
- Preserve user data by backing up existing files before replacing them
- Treat GPG and SSH permissions as part of the contract

## Verification

Run these checks after changing shell startup or bootstrap behavior:

```bash
bash tests/run-tests.sh config
bash tests/run-tests.sh functions
bash tests/run-tests.sh compliance
```

Helpful direct checks:

```bash
bash --noprofile --norc -c 'set -u; source .config/env.d/platform.sh'
zsh -c 'set -u; source .zshrc.d/env.sh'
make check
```

## Troubleshooting

### Shell startup is slow

```bash
time bash -i -c exit
time zsh -i -c exit
```

### Shared environment fails to load

```bash
bash --noprofile --norc -c 'set -u; source .config/env.d/platform.sh'
```

If this fails, check for unguarded variable reads in shared shell files.

### Symlinks look wrong

```bash
make status
make clean
make bootstrap
```

### Permissions look wrong

```bash
make audit
```

### GPG or SSH is unavailable

Verify that the relevant binaries are on `PATH`, then check the sockets and permissions under `~/.gnupg` and `~/.ssh`.

## Notes

- Legacy examples remain in `examples/`
- Current template stubs live in `templates/`
- `bin/pinentry-fallback` should remain the only pinentry path referenced from the tracked GPG config
- The `tree` helper in `shared/aliases.sh` is a function wrapper. Use `\tree` or `command tree` to invoke the system binary directly.

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

`.profile.local` is sourced by `.zshrc` after `platform.sh` loads, so user PATH
additions take precedence over system directories.

### Shared interactive layer

Both shells load shared configuration:

```text
# .bashrc loads directly:
.config/env.d/platform.sh
.config/env.d/foundry.sh
shared/functions.sh
shared/aliases.sh
shared/prompt.sh
~/.profile.local (after platform.sh, with double-sourcing guard)

# .zshrc loads via its own entrypoint:
.profile
.zprofile
.zshrc
.zshrc.d/prompt.sh
.config/env.d/platform.sh
.config/env.d/foundry.sh
shared/functions.sh
shared/aliases.sh
~/.profile.local (after platform.sh, with double-sourcing guard)
```

Both shells now consistently load `foundry.sh` and `prompt.sh` if available.
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
├── examples/
│   ├── gitconfig-local-example
│   ├── forward-local-example
│   ├── zshrc-local-example
│   ├── vimrc-local-example
│   └── ssh-config-example
├── secrets/
│   ├── secrets.secrets.yaml.example
│   ├── secrets.yaml          (gitignored decrypted working copy)
│   └── secrets.enc.yaml      (committed encrypted store)
└── .sops.yaml                (SOPS configuration with public age key)
```

## SOPS + age Secret Management

Secrets are managed with [SOPS](https://github.com/getsops/sops) and [age](https://age-encryption.org/). The encrypted store is committed to git; the decrypted working copy is gitignored.

### Setup

Run once per machine:

```bash
make secrets-init
```

This generates an age keypair at `~/.config/sops/age/keys.txt`, updates `.sops.yaml` with the public key, and bootstraps the encrypted store.

**Backup the private key immediately:**

```bash
cp ~/.config/sops/age/keys.txt ~/safe-backup/
```

### Workflow

```bash
make secrets-edit      # Open encrypted secrets in editor (via sops)
make secrets-encrypt   # Re-encrypt secrets/secrets.yaml -> secrets.enc.yaml
make secrets-decrypt   # Decrypt secrets.enc.yaml -> secrets/secrets.yaml
make secrets-list      # List secret keys in the default namespace
```

### Accessing Secrets in Shell

Secrets are **never exported at startup**. Use the on-demand functions in `shared/functions.sh`:

```bash
# Read a secret value (prints to stdout)
secret github_token dotfiles

# Run a command with a secret injected as an env var (never exported)
with_secret GITHUB_TOKEN=github_token -- gh repo list

# List all keys
secret_list dotfiles
```

Secret layout in `secrets/secrets.yaml`:

```yaml
dotfiles:
  github_token: "..."
  gitlab_token: "..."

personal:
  email_smtp_password: "..."
```

Access via `secret <key> <namespace>` (e.g., `secret github_token dotfiles`).

### Security Model

- Encryption key: age (public-key cryptography)
- Public key: committed in `.sops.yaml` (safe to share)
- Private key: stored at `~/.config/sops/age/keys.txt` (never commit)
- Committed file: `secrets/secrets.enc.yaml` (unreadable without private key)
- Working copy: `secrets/secrets.yaml` (gitignored, `chmod 600`)

### Multi-Machine Sync

To add a new machine:

1. Copy `~/.config/sops/age/keys.txt` from an existing machine (or import via key backup)
2. Run `make secrets-encrypt` to sync the committed encrypted file
3. The new machine can now decrypt `secrets.enc.yaml`

## Bootstrap Behavior

`make bootstrap` and `./bootstrap.sh` are linkers, not installers.

The bootstrap flow:

1. Back up any existing target file once
2. Symlink the repo file into place
3. Create `~/.gnupg` and `~/.ssh` with restrictive permissions
4. Set `core.hooksPath` if `.githooks/` exists
5. Print reminders for optional local override files

The bootstrap must stay idempotent. Running it twice should not duplicate backups or corrupt existing links.

## NixOS / WSL Notes

This repo is shell- and file-based, so it works on NixOS and WSL, but the
package-manager assumptions differ from macOS and generic Linux.

### NixOS

- Do not install `python3`, `node`, or shell tools with `apt` or other
  foreign package managers.
- Prefer declarative Nix shells or profiles for development tooling:
  - Python: via `uv` / `mise`, not system `python3`
  - Node: via `pnpm` / `mise`, not system `node`
  - Linters: `shellcheck`, `shfmt`, `sops`, `age` via `nix-shell` or `mise`
- If you need `python3` for system scripts, use `nix-shell -p python3` or add
  it to your Nix user profile.

### WSL

- Windows paths live under `/mnt/c/...`, `/mnt/d/...`, etc.
- For interactive shells, Windows Terminal with the WSL profile is the
  recommended terminal.
- This host does not support mirrored networking mode; WSL networking is
  NAT-based.
- Prefer WSL-native CLI tool installs (`nix`, `mise`, `pnpm`) over
  Windows-side binaries when the tool must be invoked from shell startup.

### What this repo does not do

- It does not provision packages for NixOS or WSL.
- `MacPorts` is macOS-only and is ignored automatically on other platforms.
- `mise` remains optional; if absent, the shell continues without shims.

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

Run the project bash suites directly:

```bash
bash tests/verify-dotfiles.sh
bash tests/test-functions.sh
bash tests/test-bootstrap.sh
bash tests/test-secrets.sh
```

If `make` is available in your environment, you can also use:

```bash
make verify
make test
```

Helpful direct checks:

```bash
bash --noprofile --norc -c 'set -u; source .config/env.d/platform.sh'
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

# Dotfiles Manual

## Architecture

This repo is organized around a small number of clear responsibilities:

- `bootstrap.sh` links files into `$HOME` and applies permissions
- `.profile` provides the POSIX shared base for all login shells
- `.bash_profile` and `.zprofile` load `.profile`
- `.bashrc` and `.zshrc` load the shared interactive environment
- `shared/platform.sh` holds shared environment defaults
- `.config/env.d/foundry.sh` provides optional Ethereum development wrappers
- `shared/functions.sh` and `shared/aliases.sh` expose cross-shell helpers
- `.zshrc.d/prompt.sh` provides zsh-specific prompt formatting
- `bin/` contains small user-facing helper executables
- `scripts/` contains verification, maintenance, and cleanup helpers
- `.ci/` contains GitLab CI pipeline definition and helpers

The repo does not automate package installation. It assumes required tools are installed manually.

`mise` is supported as an optional per-user developer tool manager for language runtimes and shims, but it is not part of bootstrap or system provisioning.

## Shell Load Order

### bash login shell

```text
~/.bash_profile -> ~/.profile -> ~/.bashrc
```

`.profile` sources `.profile.local` once (the `DOTFILES_PROFILE_LOCAL_LOADED`
guard prevents a second load). `.bash_profile` sources `.profile`, so a login
shell loads it there, before `platform.sh` builds `PATH`; only in an interactive
non-login bash (where `.profile` never runs) does `.bashrc` load it after
`platform.sh`, so its `PATH` additions take precedence only in that case.

### zsh login shell

```text
~/.zprofile -> ~/.profile -> ~/.zshrc
```

Under zsh `.zshrc` sources `.profile` on every interactive or login start, so
`.profile.local` is loaded there once, before `platform.sh`; its `PATH` additions
do not take precedence over the system directories.

### Shared interactive layer

Both shells load shared configuration:

```text
# .bashrc loads directly:
shared/platform.sh
shared/functions.sh -> shared/secrets.sh
shared/aliases.sh
shared/prompt.sh
.config/env.d/*.sh (proxy, foundry, user-local-bin)
~/.profile.local (loaded once per session)

# .zshrc loads via its own entrypoint:
.profile
shared/platform.sh
shared/functions.sh -> shared/secrets.sh
shared/aliases.sh
shared/prompt.sh
.config/env.d/*.sh (proxy, foundry, user-local-bin)
.zshrc.d/prompt.sh
~/.profile.local (loaded once per session)
```

Both shells now consistently load `foundry.sh` and `prompt.sh` if available.
`.profile.local` is loaded exactly once per shell session, from `.profile`
whenever it runs (every login shell, and every interactive or login zsh session
because `.zshrc` sources `.profile`); only an interactive non-login bash loads it
from `.bashrc`, after `platform.sh`.

A non-interactive, non-login shell (`sh -c`, `bash -c`, `zsh -c`) reads none of
these files, so per-host settings are not applied there.

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

### Encrypt / decrypt mechanics

The store is two files:

- `secrets/secrets.yaml` — plaintext, **gitignored**, `chmod 600`, local only.
- `secrets/secrets.enc.yaml` — encrypted, **committed**, useless without the private age key.

The `.sops.yaml` `creation_rules.path_regex` selects which plaintext file gets
encrypted (`secrets/[^.]*\\.yaml$` → matches `secrets/secrets.yaml`, excludes the
already-encrypted `secrets/secrets.enc.yaml`). The recipient age public key is
also in `.sops.yaml`; only the holder of the matching private key can decrypt.

**Encrypt (plaintext → enc)**

1. Edit the plaintext: `make secrets-edit` (opens `secrets.yaml` via `sops edit`,
   or hand-edit it).
2. `make secrets-encrypt` → `_sops_encrypt` in `shared/secrets.sh` runs
   `sops encrypt --output secrets/secrets.enc.yaml secrets/secrets.yaml`.
   sops generates a random data key, encrypts each YAML value with it, wraps
   the data key with the age public key, and writes the `.enc.yaml`.
3. Commit `secrets.enc.yaml`. The plaintext never leaves the machine.

**Decrypt (enc → value, on demand)**

- `secret <key> <namespace>` calls `_sops_decrypt` (`sops -d secrets/secrets.enc.yaml`,
  STDOUT) and parses the requested field. The result is cached in-memory for the
  session — no plaintext is written to disk unless you explicitly `make secrets-decrypt`.
- `with_secret VAR=key -- cmd` injects a single secret as an env var for one command
  and never exports it to the shell.

**Why the command shape matters**

- `sops` requires flags *before* the input file. The correct form is
  `sops encrypt --output OUTFILE INFILE`. A trailing `-o OUTFILE` is ignored
  (sops treats it as a second positional) and silently writes ciphertext to
  stdout instead of the file — the enc file would never update.
- The `path_regex` must match the *plaintext input*, not the `.enc.yaml` output,
  or `sops` fails with `no matching creation rules found` and encrypts nothing.

Round trip: `edit secrets.yaml` → `make secrets-encrypt` → `git commit .enc.yaml`,
then anywhere `secret github_token dotfiles` decrypts on demand.

### Accessing Secrets in Shell

Secrets are **never exported at startup**. Use the on-demand functions in `shared/secrets.sh`:

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

## Git Hooks

`bootstrap.sh` points `core.hooksPath` at `.githooks/`.

- `pre-commit` — format/lint checks and secret detection.
- `pre-push` — refuses to push a topic branch to a non-authoritative remote.

The `pre-push` hook resolves the authoritative remote from your own clone's
config (`branch.<default>.remote`); it hardcodes no host or remote name. It
exits immediately on a single-remote clone, so it is a no-op unless you have
several remotes and one of them is a mirror. Pushing the default branch or
tags to a mirror is still allowed, so mirror syncing keeps working. Override
with `git push --no-verify`.

## CI / GitLab CI

Continuous integration runs on GitLab CI (GitLab is the authoritative SCM).
The pipeline is defined in `.gitlab-ci.yml` (which includes `.ci/gitlab-ci.yml`).
It runs in two stages:

- `sast` — parallel static analysis jobs (shellcheck, shfmt, python-lint)
- `test` — behavioral tests (`make test` + `make test-zsh`)

The pipeline uses Alpine 3.20.5 for environment parity.

Local parity: `make ci-local` runs the pipeline locally via `act` (GitHub Actions
runner) or `glab` CLI.

### Verifying pipeline status

GitLab CI reports pipeline status natively to GitLab's commit/MR UI — no Status
API workaround needed. The source of truth is GitLab itself:

```bash
make ci-check        # latest pipeline must be 'success' AND cover HEAD
```

`make ci-check` reads the latest pipeline via the GitLab API (using `glab` or
`GITLAB_TOKEN`), exiting non-zero if the latest pipeline is not green **or**
was built for an older commit than HEAD. The coverage check catches a stalled
webhook. Pass `--no-coverage` to `.ci/scripts/gitlab-ci-verify.sh` to check
status only.

### Merge workflow (merge commits)

**AGENTS.md "Branch-Based Workflow" is the single source of truth.** This section
exists to explain *why*; it does not define the rules.

The project merges with GitLab's **merge commit** method. A topic branch is therefore
never rewritten: its GPG-signed commits land on `main` unchanged, keeping author and
committer on the key's uid email. GitLab cannot sign, so the merge commit it authors
is unsigned — that is expected, and the reason to judge history integrity by the
branch commits, not by the merge commit GitLab adds.

This section previously claimed a fast-forward-only policy and instructed the reader
to `git rebase origin/main` followed by `force-with-lease`. That was wrong on both
counts: the repository does not use fast-forward (see the 14 merge commits on
`main`), and rebasing a published signed branch to recover rewrites signed history and
invalidates every signature in it. If you arrived here following that advice, restore
the branch instead:

```bash
git fetch origin
# Refuse to continue with uncommitted work: `reset --hard` would discard it, and a
# backup branch only preserves committed state.
git status --porcelain                      # must be empty
git branch backup/<name>-before-recovery    # keep the rewritten state, do not delete
git reset --hard origin/<name>              # only on a branch with no open MR
```

Stash or commit anything outstanding first (`git stash push -u`, or a WIP commit on
the backup branch). `git reset --hard` discards staged and working-tree changes, and
the backup branch does **not** capture them.

If the branch has an open MR, do **not** reset it. Ask the maintainer; a force-push
to a shared, published branch needs explicit authorization.

Syncing a branch that has fallen behind `main` is a **merge**, not a rebase:

```bash
git fetch origin
git merge origin/main        # private branch: rebase is still fine, it re-signs
git push                     # published branch: plain push, no force
```

An **unpublished** branch — one that exists only locally, with no upstream yet — may
be rebased freely, because `commit.gpgsign` re-signs each recreated commit and the
old SHAs were never published:

```bash
git rebase origin/main       # only before the first push of this branch
git push -u origin <name>    # first push: no force needed, nothing to rewrite
```

Once a branch has been pushed it is **published**, even if nobody else has pulled
it. From that point the `pre-push` guard rejects any non-fast-forward update, so
`git rebase` + `git push --force-with-lease` will be refused. Merge instead:

```bash
git fetch origin
git merge origin/main
git push
```

To rebase a branch that was pushed by mistake, delete the remote branch first
(`git push origin --delete <name>`) and then push the rewritten local branch as new.

The `dotfiles-check.sh` behind-warning at shell init is your cue that `main` has
moved and a sync is due. Both the NixOS and macOS working copies must merge
`origin/main` before merging the MR.

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

## Troubleshooting

### Shell startup is slow

```bash
time bash -i -c exit
time zsh -i -c exit
```

### Shared environment fails to load

```bash
bash --noprofile --norc -c 'set -u; source shared/platform.sh'
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

# AGENTS.md

## Role

This repo is a cross-platform dotfiles home. Use it to manage shell startup, Git, SSH, GPG, editor config, and small helper scripts. Keep it file-based. Do not turn it into a package-manager or provisioning system. Keep private secrets out of git. Keep the repo small, clear, and reviewable.

> [!IMPORTANT]
> Mask credentials, secrets, and API keys in conversation: never echo raw values, show provider prefix + `****` + last 4 (e.g. `ghp_****...****rMJ`). Reference secrets by name from the encrypted store, never store pasted keys in plaintext. Keep this rule mirrored in persistent memory and update both when it changes.

## Precedence

1. Follow higher-priority user or system instructions first.
2. Treat this file as the repo-wide default policy.
3. Prefer more specific repo docs or task plans only when they do not conflict here.

## Core Rules

- Keep startup minimal and idempotent.
- Shared config should load once, then be reused by bash and zsh.
- Detect optional tools; do not install them.
- Back up existing user files before replacing them.
- Preserve privacy and permissions for GPG, SSH, and secret-bearing files.
- Keep changes small and reviewable.
- Use `mise` for project-scoped tooling (shellcheck, shfmt, age, sops) and global runtimes (uv/python, pnpm/node).
- Use MacPorts only for system packages (git, gpg, coreutils, python3 for system scripts).
- All external dependencies fetched via `curl`/`wget` with SHA256 verification — never package managers in bootstrap/startup.
- Pin all versions in `.mise.toml` and CI workflows.

## Repo Layout

- `bootstrap.sh` links tracked files into `$HOME` and applies permissions.
- `.profile` is the shared POSIX base for login shells.
- `.bash_profile`, `.bashrc`, `.zprofile`, and `.zshrc` are shell entrypoints.
- `.config/env.d/` holds shared environment loaders.
- `shared/` holds cross-shell functions and aliases.
- `bin/` holds small executables expected on `PATH`.
- `scripts/` holds maintenance and verification helpers.
- `tests/` holds syntax and behavior checks.
- `templates/` and `examples/` hold user-editable starting points.

## Cross-Platform Guidance

- Prefer POSIX shell patterns where possible.
- Use OS-specific branches only when behavior truly differs.
- Keep macOS and Linux paths explicit.
- Avoid GNU-only assumptions when a BSD-compatible fallback exists.
- Do not hardcode package-manager workflows or install commands into normal startup.
- `mise` shims take precedence over system package managers in PATH.
- Use `mise exec` or `mise run` to invoke project tools; do not hardcode mise paths.
- Global runtimes (Python via `uv`, Node supplied by `pnpm`'s bundled Node.js) managed by `mise use --global`.

## No Package Manager Automation

- Never make bootstrap or startup scripts install software.
- It is fine to print manual install guidance when a tool is missing.
- Keep docs honest about prerequisites.
- If a required tool is absent, fail clearly and early.
- `mise` is the **only** allowed tool manager for developer runtimes and shims.
- MacPorts is restricted to system packages (git, gpg, coreutils).
- All other dependencies fetched via `curl`/`wget` with SHA256 verification.

## Mise Configuration

### Project Tools (`.mise.toml`)
- `shellcheck` — linting
- `shfmt` — formatting
- `age` / `age-keygen` — secret key generation
- `sops` — secret encryption

### Global Runtimes (via `mise use --global`)
- `python` — via `uv` (preferred over system python3)
- `node` — via `pnpm` (pnpm bundles its own Node.js; no separate `mise use --global node` pin is required)

### PATH Order (in `shared/platform.sh`)
1. mise global shims (`~/.local/share/mise/shims`)
2. Project mise shims (auto via `mise activate` in shell rc)
3. User `~/bin`, `~/.local/bin`
4. Foundry (if installed)
5. MacPorts (`/opt/local/bin`, `/opt/local/sbin`)
6. System paths

### Verification
Run `scripts/verify-migration.sh` after any mise/MacPorts changes.

## Git Commit Signing

- Prefer **signed commits** so history is verifiable and shows "Verified" on GitHub/GitLab.
- The signing preference lives in gitconfig — set per-repo (local) or globally:
  - local: `git config --local commit.gpgsign true`
  - global: `git config --global commit.gpgsign true`
  - also enable `tag.gpgsign true` if tags should be signed.
- The signing backend and key are configured with `gpg.format` and `user.signingkey`
  (again, either `--local` or `--global`).
- Author commits with the email that matches the GPG key's uid,
  not the forge's private noreply address. A valid signature shows
  "Unverified" on GitHub/GitLab only when the **public key is not
  uploaded** to the account — upload it (Settings → SSH and GPG keys) to
  get the green "Verified" check. The commit email need not be a forge-owned
  domain as long as the signing key is registered.
- Some users prefer **SSH signing** over GPG: set `gpg.format = ssh`,
  point `user.signingkey` at the SSH public key path, and register the key on
  GitHub/GitLab. SSH signing reuses keys devs already have and avoids the GPG
  agent/pinentry setup.
- Verify before pushing: `git log --show-signature -1` or `git verify-commit HEAD`.
- Do not rewrite or force-push already-published signed history unless coordinated;
  re-signing rewrites commit hashes and diverges from every clone/remote.

## Cursor Plans

- Use `.cursor/plans/` only for temporary plan drafts.
- Keep plan files out of git if the directory is ignored.
- One plan per task or feature.
- Include target files, edit order, and verification commands.
- Do not place runtime code or bootstrap logic there.
- Promote durable guidance into `AGENTS.md`, `README.md`, or `MANUAL.md`.

## Verification

- Run shell syntax checks after startup-file edits.
- Run targeted tests for environment loading, prompt helpers, and bootstrap behavior.
- Re-check docs when file names, paths, or startup order change.
- Verify permissions-sensitive files after bootstrap changes.

## Change Discipline

- Prefer direct edits over broad refactors.
- Keep docs, tests, and code in sync.
- Introduce new dependencies only when they are strictly necessary.
- Use explicit file ownership and clear naming over clever shell indirection.

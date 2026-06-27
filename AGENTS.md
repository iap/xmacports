# AGENTS.md

## Role

This repo is a cross-platform dotfiles home. Use it to manage shell startup, Git, SSH, GPG, editor config, and small helper scripts. Keep it file-based. Do not turn it into a package-manager or provisioning system.

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

## No Package Manager Automation

- Never make bootstrap or startup scripts install software.
- It is fine to print manual install guidance when a tool is missing.
- Keep docs honest about prerequisites.
- If a required tool is absent, fail clearly and early.

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

# Contributing

Thanks for contributing to these dotfiles.

## Prerequisites

- `mise` for project tooling and runtimes
- Git with GPG signing configured
- GPG key registered locally (see AGENTS.md Git Commit Signing for the signing
  conventions; your key id lives in `~/.gitconfig.local`, never in tracked files)

## Setup

```bash
git clone git@gitlab.com:iap/xmacports.git ~/.dotfiles
cd ~/.dotfiles
make bootstrap
mise install
```

## Toolchain

- Shell lint/format: `shellcheck`, `shfmt` via `mise`
- Secrets: `age`, `sops` via `mise`
- Python lint: `ruff` via `uv`

## Branch Naming

Use kebab-case with a scope prefix (`<scope>/<short-name>`). Branch names
never use the `type(scope):` form — that shape is reserved for commit subjects.

```
fix/audit-2026-09
feat/secrets-sync
docs/readme-branch-naming
```

Examples:
- `feat/secrets-sync`: add multi-machine sync
- `fix/ci-label-jobs`: migrate from Drone to GitLab CI
- `docs/readme-branch-naming`: document the branch naming convention

## Commits

- All commits should be GPG-signed (see AGENTS.md for signing configuration).
- If pinentry blocks signing in a non-interactive shell, use a terminal with agent access or ask before switching signing methods.
- Follow the `type(scope): summary` format. Body explains what changed and why.

## Secrets

- Encrypted store: `secrets/secrets.enc.yaml`
- Decrypt on demand with `secret()`, `with_secret()`, or `secrets_decrypt()`
- Never commit plaintext secrets or age keys

## Tests

```bash
make test
make test-zsh
make verify
```

## Lint

```bash
make shellcheck
make fmt-check
make python-lint
make test-compliance
```

## Documentation

When writing or editing documentation, use GitHub/GitLab alert syntax:

```markdown
> [!NOTE]
> Supplemental information that's not critical to follow.

> [!TIP]
> Helpful suggestion for a better workflow or outcome.

> [!IMPORTANT]
> Critical information the reader must follow to avoid breakage.

> [!WARNING]
> Potential risk — data loss, security issue, or irreversible action.

> [!CAUTION]
> Stronger than WARNING — destructive or dangerous if ignored.
```

See AGENTS.md for the full reference with usage guidance.

## Merge Request Workflow

1. Create a topic branch from `origin/main`
2. Make focused, single-purpose commits
3. Rebase onto latest `origin/main` before submitting
4. Open an MR against `main`
5. Ensure CI is green (GitLab CI runs on every push)
6. Fast-forward merge only — no merge commits

## CI

- Primary CI: GitLab CI (`.gitlab-ci.yml` includes `.ci/gitlab-ci.yml`)

## Merge policy

- The project uses **fast-forward** merges only. Rebase your branch onto the
  authoritative remote before merging (see MANUAL.md for the full workflow).
- Never force-push `main`.

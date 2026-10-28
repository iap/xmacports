# Claude Code — Project Context

This file is read by Claude Code on startup. It provides project-specific context
that supplements the global agent instructions.

## Project identity

**xmacports** — a cross-platform dotfiles configuration repository. Tracked files
are symlinked into `$HOME` by `bootstrap.sh`. The repository is public; every
tracked byte is world-readable. Never commit personal identity, secrets, or
machine-specific paths.

- **Forge:** GitLab (`git@gitlab.com:iap/xmacports.git`)
- **Primary host:** macOS (Darwin, bash 3.2)
- **Secondary host:** Windows + WSL (nixos)
- **Canonical checkout:** `~/.dotfiles`
- **Private overlay:** `~/.dotfiles-private` (keybase-encrypted, untracked)

## Quick reference

```bash
make test          # run full test suite (bash)
make test-zsh      # zsh load-chain smoke test
make shellcheck    # lint all shell scripts
make fmt-check     # check shell formatting
make verify        # audit + verification scripts
make bootstrap     # link tracked files into $HOME
make audit         # permission and compliance check
```

## Critical rules (from AGENTS.md)

1. **Never push to `main`** — all changes go through merge requests.
2. **Sign every commit** — SSH signing with `~/.ssh/id_ed25519`, noreply email.
3. **No personal data in tracked files** — no emails, key IDs, absolute paths, machine names.
4. **No `git add .`** — stage specific files only.
5. **No secrets in plaintext** — use SOPS + age; `make secrets-encrypt`.
6. **Cross-platform** — bash 3.2 on macOS; test on both hosts.
7. **Run `make shellcheck && make fmt-check && make test`** after shell changes.

## Key files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Critical operating rules (short version) |
| `CONTRIBUTING.md` | Single source of truth — architecture, workflow, CI, troubleshooting |
| `README.md` | User-facing documentation |
| `docs/architecture.md` | System architecture and load chains |
| `docs/style-guide.md` | Documentation formatting conventions |
| `bootstrap.sh` | Links tracked files into `$HOME` |
| `.gitconfig` | Shared git defaults (no identity — lives in `~/.gitconfig.local`) |
| `shared/platform.sh` | XDG defaults, PATH assembly, platform detection |
| `.githooks/` | pre-commit, commit-msg, pre-push guards |

## Architecture summary

Shell load chain:
- bash login: `~/.bash_profile` → `~/.profile` → `~/.bashrc`
- zsh login: `~/.zprofile` → `~/.profile` → `~/.zshrc`
- Interactive: `shared/platform.sh` → `shared/functions.sh` → `shared/secrets.sh`

See `docs/architecture.md` for full details.

## Common tasks

- **Add a new script:** create in `scripts/`, make executable, add tests, run `make shellcheck`
- **Add a new shared function:** add to `shared/functions.sh` or `shared/aliases.sh`, test in both bash and zsh
- **Add a new config file:** add to tracked root, update `bootstrap.sh` to link it, update README layout table
- **Modify CI:** edit `.ci/gitlab-ci.yml`, test with `make ci-local` or push to branch
- **Add a secret:** `make secrets-edit`, then `make secrets-encrypt`, commit only `.enc.yaml`

## Agent instructions

For detailed rules, read `AGENTS.md`. For architecture and workflow, read
`CONTRIBUTING.md`. If the two disagree, `CONTRIBUTING.md` is correct.

@AGENTS.md

# Onboarding

This guide helps new contributors and AI agents get started with the xmacports
dotfiles repository.

## For humans

### 1. Clone and bootstrap

```bash
git clone git@gitlab.com:iap/xmacports.git ~/.dotfiles
cd ~/.dotfiles
make bootstrap
mise install
```

### 2. Set up identity (required)

```bash
cp examples/gitconfig-local-example ~/.gitconfig.local
# Edit ~/.gitconfig.local with your name, email, and signing key
```

### 3. Run tests

```bash
make test          # full suite
make test-zsh      # zsh smoke test
make shellcheck    # lint
make fmt-check     # formatting
```

### 4. Read the docs

1. [README.md](../README.md) — what this does, layout, security
2. [CONTRIBUTING.md](../CONTRIBUTING.md) — architecture, workflow, CI, troubleshooting
3. [docs/architecture.md](architecture.md) — system architecture and load chains
4. [docs/style-guide.md](style-guide.md) — documentation formatting

### 5. Make changes

1. Create a branch: `git checkout -b scope/short-name`
2. Make changes, run tests
3. Commit with scoped type: `type(scope): summary`
4. Push and open MR: `git push -u origin <branch> && glab mr create`

## For AI agents

### First steps

1. Read `AGENTS.md` — critical rules (short, must-follow)
2. Read `CONTRIBUTING.md` — single source of truth
3. Read `docs/architecture.md` — system architecture
4. Read `CLAUDE.md` — Claude-specific context

### Before making changes

1. **Check the environment** — are you on macOS or WSL? Run `uname -s`.
2. **Check git state** — `git status`, `git branch`, `git log --oneline -5`.
3. **Read relevant files** — never guess file contents; use `read_file` or `cat`.
4. **Check existing tests** — run `make test` before changes to establish baseline.

### Making changes

1. **Prefer direct edits** over broad refactors.
2. **Stage files explicitly** — never `git add .`.
3. **Run verification** after changes: `make shellcheck && make fmt-check && make test`.
4. **Sign commits** — SSH signing with `~/.ssh/id_ed25519`.
5. **One logical change per commit** — scoped type prefix.

### Critical constraints

- **Never push to `main`** — all changes via merge requests.
- **No personal data in tracked files** — no emails, key IDs, absolute paths, machine names.
- **No secrets in plaintext** — use SOPS + age.
- **Cross-platform** — test on both macOS and Linux/WSL.
- **bash 3.2 compatibility** — macOS ships bash 3.2; avoid bash 4+ features.
- **No `git add .`** — sweeps in untracked files.

### Common pitfalls

| Pitfall | How to avoid |
|---------|-------------|
| Forgetting to run tests | Always run `make test` before committing |
| Breaking bash 3.2 compat | Test with `/bin/bash` (macOS system bash) |
| Committing secrets | Pre-commit hook blocks, but don't rely on it — stage explicitly |
| Hardcoding home paths | Use `$HOME`, `~/`, or `DOTFILES_ROOT` |
| Mixing platform-specific code | Gate behind `is_macos()` / `is_linux()` |
| Editing tracked .gitconfig identity | Identity lives in `~/.gitconfig.local` (private overlay) |

### Testing checklist

```bash
make shellcheck    # lint
make fmt-check     # format
make test          # full suite
make test-zsh      # zsh smoke test
make verify        # audit + structural
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `make test` fails on test-functions.sh | Pre-existing failure (git_prompt_info) — not your concern |
| `git commit` fails "gpg failed to sign" | Check `git config gpg.format` and `user.signingkey` |
| `make shellcheck` not found | Install via `mise install` or package manager |
| Pre-commit hook rejects `*.asc` | Whitelist the specific path in `.githooks/pre-commit` |
| Pipeline fails on fork MR | Check `CI_MERGE_REQUEST_PROJECT_ID` is set |

### File ownership map

See [docs/architecture.md](architecture.md) for the full component ownership table.

### Key environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_ROOT` | `~/.dotfiles` | Repository root |
| `DOTFILES_ENABLE_GH` | unset | Enable GitHub CLI config linking |
| `DOTFILES_ENABLE_FISH` | unset | Accepted but no fish files tracked |
| `XDG_CONFIG_HOME` | `~/.config` | XDG config directory |
| `XDG_DATA_HOME` | `~/.local/share` | XDG data directory |
| `XDG_CACHE_HOME` | `~/.cache` | XDG cache directory |

### Related documents

- [README.md](../README.md) — user-facing documentation
- [CONTRIBUTING.md](../CONTRIBUTING.md) — single source of truth
- [AGENTS.md](../AGENTS.md) — critical operating rules
- [CLAUDE.md](../CLAUDE.md) — Claude Code context
- [docs/architecture.md](architecture.md) — system architecture
- [docs/style-guide.md](style-guide.md) — documentation formatting

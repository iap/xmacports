# Dotfiles

Cross-platform home directory configuration: deterministic shell startup, a
file-based bootstrap, and no package-manager automation.

**Authoritative remote:** [GitLab](https://gitlab.com/iap/xmacports.git) ·
**Mirror:** [GitHub](https://github.com/iap/xmacports)

> [!NOTE]
> Naming: the forge repo is called `xmacports` for history; the canonical
> checkout path is `~/.dotfiles`. Never rename either to match the other, and
> resolve paths through `DOTFILES_ROOT` rather than a hardcoded `~/xmacports`.

## What this does

- Links shell, Git, SSH, GPG, and editor configuration into `$HOME`
- Keeps shared environment logic in one place, reused by both bash and zsh
- Provides small helper scripts for inspection, cleanup, and verification
- Supports per-machine override files and an optional private overlay

Nothing here installs software at bootstrap or shell startup: they only
link files, apply permissions, and report missing tools. The pinned git
source build is the one manual exception (see "Git source build").

## Quick start

```bash
git clone git@gitlab.com:iap/xmacports.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
make test
```

## Prerequisites

| Tool | Why it is needed | Provided by |
|------|------------------|--------------|
| `bash`, `zsh` | The two supported shells | System |
| `git` | Version control and commit signing | System / MacPorts |
| `gpg`, `gpgconf`, `pinentry` | Signing commits | System / MacPorts |
| `make` | Task runner for every command below | System |
| `mise` | Installs and pins the tools below | [mise.sh](https://mise.jdx.dev) |
| `shellcheck` 0.10.0 | Shell linting (`make shellcheck`) | `mise install` |
| `shfmt` 3.8.0 | Shell formatting (`make fmt-check`) | `mise install` |
| `age` 1.2.1 | Secret encryption | `mise install` |
| `sops` 3.9.4 | Encrypted secret store | `mise install` |
| `python` 3.11.16, `uv` 0.5.4 | Python runtime and tooling | `mise install` |
| `nodejs` 20.17.0, `pnpm` 9.0.2 | Node workspace dependencies | `mise install` |
| `ruff` | Python linting (`make python-lint`) | `uv tool install ruff` |
| `jq`, `curl` | CI-only; used by the MR attribution job | System |

Versions are pinned in `.mise.toml`. `ruff` is the one exception — it is
installed through `uv`, not `mise`, because `mise`'s backend cannot verify its
attestation in this environment.

`mise` is the only tool manager used for developer runtimes and shims. MacPorts
is restricted to system packages (`git`, `gpg`, `coreutils`).

## Layout

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Links tracked files into `$HOME`, applies permissions |
| `.profile` | POSIX shared base for every login shell |
| `.bash_profile`, `.bashrc` | bash entrypoints |
| `.zprofile`, `.zshrc` | zsh entrypoints |
| `.zshrc.d/` | zsh-only prompt and helpers |
| `shared/` | Cross-shell functions, aliases, prompt, secrets |
| `shared/platform.sh` | XDG defaults, `PATH` assembly, GPG agent discovery |
| `.config/env.d/` | Optional env modules (proxy, foundry, user-local-bin) |
| `.config/gpg/` | `gpg.conf` and `gpg-agent.conf` |
| `.config/ssh/config` | SSH configuration |
| `.config/vim/` | XDG vim runtime and privacy settings |
| `bin/` | Small helpers expected on `PATH` |
| `scripts/` | Maintenance and verification helpers |
| `scripts/install-git-source.sh` | Manual, pinned git source build (no sudo) |
| `tests/` | Syntax and behavior checks |
| `templates/`, `examples/` | Starting points for local overrides |
| `secrets/` | SOPS + age encrypted store |
| `.githooks/` | `pre-commit`, `commit-msg`, `pre-push` guards |
| `.ci/` | GitLab pipeline definition |

## Bootstrap

`make bootstrap` is idempotent. It backs up any file it is about to replace
once, symlinks the tracked file into place, creates `~/.gnupg` and `~/.ssh`
with restrictive permissions, points `core.hooksPath` at `.githooks/`, and
reminds you about optional override files. Running it twice does not duplicate
backups or corrupt links.

## Local overrides

Machine-specific and private settings belong in untracked files, never in
tracked config:

```bash
# Required for most users
cp templates/profile-local.example    "$HOME/.profile.local"

# Optional (copy from examples/)
cp examples/gitconfig-local-example   "$HOME/.gitconfig.local"
cp examples/forward-local-example     "$HOME/.forward.local"
cp examples/zshrc-local-example       "$HOME/.zshrc.local"
cp examples/allowed-signers-example   "$HOME/.ssh/allowed_signers"
```

## Opt-in app configs

Two app configs are tracked but linked only when you opt in. Bootstrap backs up
anything it replaces and never links secret-bearing files.

| Flag | Effect |
|------|--------|
| `DOTFILES_ENABLE_GH=1` | Links `.config/gh/config.yml` (preferences only) |
| `DOTFILES_ENABLE_FISH=1` | Accepted, but links nothing — no fish files are tracked yet |

`gh`'s `hosts.yml` holds OAuth tokens and is intentionally never tracked or
linked, so your tokens stay local.

## Security

- Secrets are never exported at startup. Use `secret()`, `with_secret()`, and
  `secret_list()` for on-demand access.
- Sensitive values are encrypted with age via SOPS and committed as
  `secrets/secrets.enc.yaml`; the decrypted working copy is gitignored.
- The store is encrypted to two age recipients — a primary machine key and an
  offline recovery key — so losing either single key leaves the store readable.
  Recipients are listed in `.sops.yaml`.
- The private age key lives at `~/.config/sops/age/keys.txt` and must never be
  committed.
- GPG and SSH config files are permission-checked by `make audit`.
- The `pre-commit` hook blocks plaintext secret files and validates that staged
  `.enc.yaml` files really contain SOPS ciphertext.

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
  manifest. The pin is the trust anchor. The manifest fetch is corroboration and
  never independent proof, because its PGP signature is not verified here. Two
  cases therefore only warn and continue: the manifest could not be fetched, or it
  was fetched but has no entry for this tarball. A disagreement between the entry
  and the pin is always fatal.
- System and package-managed prefixes (`/usr`, `/opt/homebrew`, `/opt/local`, …)
  are refused outright: the installer replaces `bin/git` and `libexec/git-core`.
- The build refuses to run below the `2.38.0` floor.
- An upgrade moves the old `bin/git` and `libexec/git-core` aside and restores them
  if `make install` fails, so a failed upgrade never leaves the prefix without a
  working git.
- After installing, open a new login shell (or `hash -r`) so `PATH` resolves the
  new binary. `shared/platform.sh` already orders `~/.local/bin` ahead of
  `/usr/local/bin` and `/usr/bin`.

To change the pinned version, edit `GIT_VERSION` and `GIT_SHA256` at the top of the
script and re-run it. Re-derive the checksum from
<https://mirrors.edge.kernel.org/pub/software/scm/git/sha256sums.asc>.

## Documentation

| Document | Audience | Read it for |
|----------|----------|-------------|
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributors | Architecture, git workflow, secrets, hooks, CI, troubleshooting |
| [AGENTS.md](AGENTS.md) | AI agents | Critical rules: environment scope, secrets, git safety, commit style |
| [docs/style-guide.md](docs/style-guide.md) | Anyone editing docs | Alert syntax, formatting, link conventions |

If you are new to the repository, read CONTRIBUTING.md first. It is the
single source of truth; AGENTS.md holds only the rules whose violation
breaks something.
| [AGENTS.md](AGENTS.md) | The short list of critical rules for agentic edits |
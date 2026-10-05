# AGENTS.md

Critical operating rules for agentic edits in this repository.

**`CONTRIBUTING.md` is the single source of truth** for architecture, git
workflow, secrets, hooks, CI, and troubleshooting. This file holds only the
rules whose violation breaks something. If the two disagree, `CONTRIBUTING.md`
is correct — fix this file in the same change set.

## Precedence

1. Follow higher-priority user or system instructions first.
2. Treat this file as the repo-wide default policy.
3. Prefer more specific repo docs only when they do not conflict here.

## Environment Scope

- This checkout runs on macOS. Fixes driven by other environments (Windows, WSL,
  other machines' layouts) belong to the agents working there.
- The agent working in an environment adjusts the project for that environment
  only; keep shared files cross-platform-safe without preempting other hosts.

## Secrets

> [!IMPORTANT]
> Mask credentials, secrets, and API keys in conversation: never echo raw
> values. Show provider prefix + `****` + last 4 (e.g. `ghp_****...****rMJ`).
> Reference secrets by name from the encrypted store, never store pasted keys in
> plaintext, and never commit an age key.

Access secrets lazily with `secret()`, `with_secret()`, and `secret_list()`. Do
not export secrets at shell startup and do not decrypt the store to read a value
into your context. `make secrets-encrypt` and commit only the `.enc.yaml`.

## Git safety

> [!IMPORTANT]
> Never push to the default branch. Not fast-forward, not force, not by any
> route. Every change reaches `main` through a merge request, so the forge
> authors the merge and history stays auditable.

- Sign commits (`commit.gpgsign true`) and author with the signing key's uid
  email, not a forge noreply address.
- Do not rewrite or force-push already-published signed history without
  coordinating — re-signing changes commit hashes and diverges from every clone.
- Once a branch is pushed it is published. Rebase only before first push; after
  that, `git merge origin/main`.
- A green pipeline is the floor, not the trigger. An MR merges only after the
  review conversation is resolved — every thread answered and closed.
- Never read `approved: true` as a review: zero approvals are required here, so
  GitLab reports that for an MR nobody reviewed. Resolved threads are the
  record; an approval is not.
- Every commit **submitted in the merge request** must be signed; `signature-check`
  blocks the merge otherwise. The merge commit GitLab itself authors is unsigned by
  necessity and is not covered; see the merge policy in CONTRIBUTING.md.
- An author may always close their own MR; no review is needed to close one.
- `--no-verify` bypasses the hooks. State it in the MR; never use it quietly.

Before any merge, confirm nothing unsigned is queued:

```bash
git log --format='%h %G?' origin/main..HEAD    # every line must show G
```

## Commit messages

- Prefix with a scoped type: `type(scope):` — `fix(secrets):`, `ci:`,
  `docs(secrets):`. One logical change per commit.
- Subject: short, direct, imperative.
- Body: what changed and why. No email addresses in prose, no `Signed-off-by:`,
  no narration of signing mechanics. Do not claim outcomes you have not verified
  — verify, then report.
- No tool-attribution footers (`Generated with …`, the Claude Code link). A
  footer naming a tool that did not write the change misattributes authorship in
  permanent public history.
- A `Co-authored-by:` trailer **is** allowed when it names a real contributor
  whose address is creditable — present in git identity, `.attribution-allow`,
  or `ATTRIBUTION_ALLOWLIST`. Do not block it. The gate judges the address, not
  the display name.

Never use alerts (`> [!NOTE]`) in commit messages — they travel as plain text,
where the syntax is literal clutter.

## Tooling

- `mise` is the **only** tool manager for developer runtimes and shims. MacPorts
  is restricted to system packages (`git`, `gpg`, `coreutils`).
- Never make bootstrap or startup scripts install software. Detect optional
  tools, do not install them. Print manual guidance when one is missing, and fail
  clearly and early when a required one is absent.
- Keep docs honest about prerequisites: state what must already exist on the host.
- Every other dependency is fetched with `curl`/`wget` and verified by SHA256.
- Introduce new dependencies only when strictly necessary.
- **Exception — git may come from a pinned source build.** Some tooling needs a
  git newer than the host's system git, and MacPorts is not always usable: it
  requires sudo, and its support matrix does not cover every macOS release. When
  that happens, build git from the official tarball into a user-owned prefix with
  `scripts/install-git-source.sh` instead of installing software ad hoc. The rules:
  - the version and its SHA256 are pinned at the top of the script; that pin is the
    trust anchor, and the checksum is verified against it
  - upstream's published manifest is fetched as a cross-check when reachable, but its
    PGP signature is **not** verified, so a match is corroboration and never independent
    proof. Both soft-fail branches are disclosed: an unreachable manifest is a warning,
    and so is a reachable manifest with no entry for this tarball. Only a disagreement
    between the entry and the pin is fatal
  - the build installs into `$HOME/.local`, never a system directory, and needs no sudo;
    system and package-managed prefixes are refused outright
  - an upgrade moves the old `bin/git` and `libexec/git-core` aside and restores them
    if the install fails, so a failed upgrade never leaves the prefix without git
  - run `--check` first, so the change in state is known before anything is written
  - the floor is `2.38.0` (required by the Graphite CLI); never pin below it
- Never invoke the installer from `bootstrap.sh` or a shell startup file. It is a
  manual, operator-run step: this repo configures a machine, it does not provision
  one.

## Shell and platform

- Keep startup minimal and idempotent. Shared config loads once, then is reused
  by bash and zsh.
- Back up existing user files before replacing them.
- Preserve privacy and permissions for GPG, SSH, and secret-bearing files.
- Prefer POSIX shell patterns; use OS-specific branches only where behavior
  genuinely differs. Do not break other hosts, but do not port their fixes
  either.
- Resolve paths through `DOTFILES_ROOT`. Never hardcode `~/xmacports`. The forge
  repo is `xmacports`; the checkout is `~/.dotfiles` — never rename either to
  match the other.
- Prefer internal, private, machine-local config over tracked public config:
  identity, signing keys, and `.local` overlays stay untracked.

## Change discipline

- Prefer direct edits over broad refactors.
- Keep docs, tests, and code in sync; update every document that mentions a
  changed path in the same change set.
- Run `make shellcheck`, `make fmt-check`, and `make test` after changes to
  shell files or startup order, and `make verify` after bootstrap or permission
  changes.

## Branch naming

Kebab-case with a scope prefix: `<scope>/<short-name>` — `fix/audit-2026-09`,
`feat/secrets-sync`. Branch names never use the `type(scope):` form; that shape
is reserved for commit subjects.

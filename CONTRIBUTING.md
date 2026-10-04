# Contributing

This is the **single source of truth** for how to work in this repository.
Architecture, git workflow, secrets, hooks, CI, and troubleshooting all live
here. `AGENTS.md` holds only the short list of critical rules an agent must not
violate and points back to this file; if the two ever disagree, this file is
correct and `AGENTS.md` is the stale copy.

## Setup

```bash
git clone git@gitlab.com:iap/xmacports.git ~/.dotfiles
cd ~/.dotfiles
make bootstrap
mise install
```

Prerequisites and pinned versions are tabulated in
[README.md](README.md#prerequisites).

## Architecture

`bootstrap.sh` links files into `$HOME` and applies permissions. Everything else
has one clear owner:

- `.profile` — POSIX shared base for all login shells
- `.bash_profile`, `.zprofile` — load `.profile`
- `.bashrc`, `.zshrc` — load the shared interactive environment
- `shared/platform.sh` — XDG defaults, `PATH` assembly, GPG agent discovery
- `.config/env.d/foundry.sh` — optional Ethereum development wrappers
- `shared/functions.sh`, `shared/aliases.sh` — cross-shell helpers
- `shared/secrets.sh` — on-demand secret access
- `.zshrc.d/prompt.sh` — zsh-only prompt formatting
- `bin/` — small user-facing helpers
- `scripts/` — verification, maintenance, cleanup
- `.ci/` — GitLab CI pipeline definition

The repo does not automate package installation and assumes required tools are
installed manually. `mise` is an optional per-user tool manager for language
runtimes and shims, not part of bootstrap or system provisioning.

### Shell load order

bash login shell:

```text
~/.bash_profile -> ~/.profile -> ~/.bashrc
```

zsh login shell:

```text
~/.zprofile -> ~/.profile -> ~/.zshrc
```

The shared interactive layer, in order:

```text
shared/platform.sh
shared/functions.sh -> shared/secrets.sh
shared/aliases.sh
shared/prompt.sh
.config/env.d/*.sh   (proxy, foundry, user-local-bin)
.zshrc.d/prompt.sh   (zsh only)
~/.profile.local     (loaded exactly once per session)
```

`~/.profile.local` is loaded exactly once per shell session, guarded by
`DOTFILES_PROFILE_LOCAL_LOADED`. `.profile` sources it, so a login shell loads
it before `platform.sh` builds `PATH`. Under zsh, `.zshrc` sources `.profile` on
every interactive or login start, so it is still loaded once, before
`platform.sh`. Only an interactive **non-login** bash loads it from `.bashrc`,
after `platform.sh` — so its `PATH` additions take precedence in that one case.

A non-interactive, non-login shell (`sh -c`, `bash -c`, `zsh -c`) reads none of
these files, so per-host settings are not applied there.

### Environment rules

`shared/platform.sh` is the central environment loader. It owns XDG directory
defaults, `PATH` assembly, GPG agent socket discovery, `GPG_TTY` setup,
optional Foundry and `mise` path discovery, default editor and locale values,
and privacy-oriented telemetry defaults.

It must remain safe to source more than once and safe under `set -u`.

### `PATH` order

1. `mise` global shims
2. `~/bin`, then `~/.local/bin`
3. Foundry, if installed
4. MacPorts (`/opt/local/bin`, `/opt/local/sbin`)
5. System paths, plus Nix profiles when present

## Make targets

| Target | Purpose |
|--------|---------|
| `make bootstrap` | Link tracked files into `$HOME`, apply permissions |
| `make test` | Behavioral test suite |
| `make test-zsh` | zsh regression lane |
| `make verify` | Migration, dotfiles, and permission checks |
| `make audit` | Permissions and secret-exposure audit |
| `make status` | Report current link/permission state |
| `make clean` | Remove `~/.dotfiles-backup-*` |
| `make shellcheck` | Shell linting |
| `make fmt-check` | `shfmt` formatting check |
| `make python-lint` | `ruff` via `uv` |
| `make test-compliance` | Repository compliance checks |
| `make secrets-init` | Generate age keypair and bootstrap the store |
| `make secrets-edit` / `-encrypt` / `-decrypt` / `-list` | Secret store operations |
| `make ci-local` | Run the pipeline locally via `act` or `glab` |
| `make ci-check` | Latest pipeline must be green **and** cover `HEAD` |

## Local overrides

Keep machine-specific and private settings in untracked files. Templates are in
`templates/`, further examples in `examples/`.

```bash
cp templates/profile-local.example   "$HOME/.profile.local"
cp examples/gitconfig-local-example  "$HOME/.gitconfig.local"
cp examples/forward-local-example    "$HOME/.forward.local"
cp examples/zshrc-local-example      "$HOME/.zshrc.local"
cp examples/allowed-signers-example  "$HOME/.ssh/allowed_signers"
```

Recognized overlays: `~/.bashrc.local`, `~/.zshrc.local`, `~/.profile.local`,
`~/.gitconfig.local`, `~/.forward.local`, `~/.ssh/config.local`.

If you keep private shell config in a separate repository, keep it outside this
one and treat it as optional. Core startup must never depend on it.

## Git workflow

> [!IMPORTANT]
> Never push to the default branch. Every change reaches `main` through a merge
> request, so the forge authors the merge and history stays auditable.

### Branch naming

Kebab-case with a scope prefix, `<scope>/<short-name>`. Branch names never use
the `type(scope):` form — that shape is reserved for commit subjects.

```text
fix/audit-2026-09
feat/secrets-sync
docs/readme-branch-naming
```

### Commits

Prefix every commit with a scoped type: `type(scope):` — for example
`fix(secrets):`, `ci:`, `docs(secrets):`. The prefix is the label; keep it
specific to the change.

- **Subject** — short, direct, imperative. The prefix plus the subject carries
  the label; do not pad it with filler.
- **Body** — state what changed and why. No email addresses in prose, no
  `Signed-off-by:` trailer, and no narration of signing mechanics. Do not claim
  outcomes you have not verified (for example "tests pass") — verify, then
  report.
- **One logical change per commit.** Do not bundle unrelated fixes.

### Commit signing

Prefer signed commits so history is verifiable and shows as verified on the
forge. Git reads config system → global (`~/.gitconfig`) → local
(`.git/config`), and **local overrides global**.

Set the signing preference and backend globally or in tracked `.gitconfig`:

```bash
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global user.signingkey 9166D30F6FE70F56
```

Author commits with the email matching the signing key's uid, not a forge
noreply address. A valid signature shows as *unverified* on the forge only when
the **public** key is not uploaded to the account — upload it under
Settings → SSH and GPG keys.

SSH signing is a supported alternative: set `gpg.format = ssh` and point
`user.signingkey` at the public key path. It reuses keys developers already have
and avoids the GPG agent and pinentry setup.

Signing is enforced on the forge by `signature-check`, not by local preference
alone. See "Signature verification" below for what that job does and does not
prove.

> [!WARNING]
> Do not silently switch signing methods on a repository whose history is
> GPG-signed, and do not rewrite or force-push already-published signed history
> without coordinating — re-signing rewrites commit hashes and diverges from
> every clone and remote.

#### Verifying SSH signatures (`allowed_signers`)

`git log --format='%G?'` only reports a good signature once git knows which
**public** keys may sign for which identity. That mapping is `~/.ssh/allowed_signers`,
named by `gpg.ssh.allowedSignersFile` in the tracked `.gitconfig`.

```bash
cp examples/allowed-signers-example ~/.ssh/allowed_signers
$EDITOR ~/.ssh/allowed_signers      # your email + PUBLIC key on one line
git log -1 --format='%G? %GS'       # want: G you@example.com
```

- The key is the **public** one. Publishing it is safe: a public key can only
  verify a signature, never create one. Never write the private key into this
  file or any tracked file.
- The principal is the email you author commits with, not the key's file comment.
- One line per identity. To rotate a key, keep the old line so history signed
  with it continues to verify.
- Bootstrap creates `~/.ssh` but deliberately does **not** create this file: it
  cannot know your email or key, and a wrong entry is worse than a missing one.

| `%G?` | Meaning |
|-------|---------|
| `G` | good signature, and the principal-to-key pair is listed |
| `U` | good signature, but that key is not listed |
| `N` | no signature, or no `allowedSignersFile` configured |
| `B` | bad signature — the commit was altered |

`U` and `G` both mean the signature is cryptographically valid; the difference is
only whether git has a trust anchor for that key.

### Merge policy

**This section is the authoritative statement of the merge policy.**

The project merges with GitLab's **merge commit** method, so the source branch is
never rewritten: its signed commits land on `main` unchanged, preserving author
and committer on the key's uid email. GitLab cannot sign, so the merge commit it
authors is unsigned — that is expected, and the reason to judge history
integrity by the branch commits rather than the merge commit GitLab adds.

1. Create a topic branch from `origin/main`
2. Make focused, single-purpose commits
3. Push the branch and open an MR
4. Let CI run
5. Answer every review thread, then resolve it (see "Merge gates" below)
6. Sync with `origin/main`, then merge

Syncing a branch that has fallen behind keeps the merge small and surfaces
conflicts early. The method depends on whether the branch is published:

```bash
# Unpublished branch (local only): rebase is safe, commit.gpgsign re-signs
git rebase origin/main
git push -u origin <name>

# Published branch: merge, never rebase, never force
git fetch origin
git merge origin/main
git push
```

Once a branch has been pushed it is **published**, even if nobody else has
pulled it. From that point the `pre-push` guard refuses any non-fast-forward
update to it on the authoritative remote. If a branch was pushed before it was
ready, and it has no open MR, the honest options are to merge instead of rebase,
or to close the MR and ask the maintainer to delete the remote branch. Do not
plan around deleting and recreating a branch yourself: the guard judges a
deletion and a new-branch push as separate, legitimate operations, so that
sequence would sidestep the rewrite rule it exists to enforce.

Before merging, confirm nothing unsigned is queued:

```bash
git log --format='%h %G?' origin/main..HEAD    # every line must show G
```

> [!CAUTION]
> `--no-verify` exists for the rare legitimate case and must be stated in the
> MR, not used quietly. Recovering a force-pushed published branch requires
> maintainer coordination; do not attempt it unilaterally.

The `dotfiles-check.sh` behind-warning at shell init is your cue that `main` has
moved and a sync is due. Every working copy must merge `origin/main` before its
MR merges.

### Merge gates

An MR merges when **the review conversation is resolved** — every discussion
thread answered and closed. A green pipeline is the floor, not the trigger: it
proves the change broke nothing, not that anyone read it.

Two things enforce that. GitLab's
`only_allow_merge_if_all_discussions_are_resolved` disables the merge button
while a resolvable thread is open, and `merge-gates` in CI reads the setting
back so it cannot be turned off unnoticed:

```bash
sh scripts/check-merge-gates.sh "$(glab repo view --output json | jq -r .id)" <mr-iid>
```

The script fails when a required setting is off, when the MR still has open
threads, or when it cannot tell — exit `0` clean, `1` gate violated, `2` could
not verify. `2` is a failure on purpose: an unverified gate is not a passing
gate. Override with `SKIP_MERGE_GATES_CHECK=1`, and say so in the MR.

**Why `approved: true` means nothing here.** This project requires zero
approvals, so GitLab reports `approved: true` on an MR nobody reviewed — the
check is vacuously satisfied. Read conversation state instead; the gate
deliberately ignores the approvals endpoint for that reason.

**A resolved thread is not a satisfied reviewer.** The author can resolve their
own thread, so this gate proves the conversation finished, not that it ended
well. Where a review app or agent leaves findings, answer in the thread before
resolving it. Resolving a thread you did not answer turns the gate into the
rubber stamp it was meant to replace.

What remains mechanical: signed commits, no force push, no rewrite of published
history, and a merge commit rather than a rebase or squash.

In CI the job asserts the policy and *reports* the conversation rather than
failing the build on it: threads get resolved after the pipeline ran, and
resolving one does not trigger a new pipeline, so a red job would latch with no
automatic way back. The forge setting evaluates the live state when the merge
button is pressed; the job makes a silent disarmament visible.

**When a second reviewer exists.** Require an approving review from a
collaborator, or from an app named in `.review-allow` that is installed on the
project and submits a real review submission — a CI status or a comment is not an
approval. The author's own approval does not count then and may not satisfy the
rule. `.review-allow` is the tracked, auditable record of which apps may
approve; changing it is a review-policy change, so review it like one. An empty
file is fail-closed and means no app may approve.

Whether an app *can* approve is a property of the forge, not of this file:
GitLab approvals are cast by users holding permission, so a bot account may be
unable to approve at all. Verify it on a throwaway MR before relying on it.

An author may always close their own MR, and no review is required to do so.
Closing is never gated, and it is also the escape hatch when a gate and your
intent disagree: close, fix, reopen.

**Settings that do not live in this repository.** Push access to `main` should
be restricted to Maintainers, and force pushes must stay disabled. Both live in
the forge UI rather than in the clone, so they are invisible to every other copy
and they decay silently. Verify them after rotating access, rather than trusting
them in advance.

### Signature verification

Every commit in an MR must be signed. The `signature-check` job fails the
pipeline when one is not, which is a floor no reviewer has to remember to check.
Run the same check locally over the same range:

```bash
sh scripts/check-signatures.sh origin/main HEAD
```

Exit `0` is clean, `1` means an unsigned or otherwise bad commit, and `2` means
the range could not be resolved. `2` is a failure on purpose: an unresolvable
base yields no commits to list, and no commits to list is indistinguishable
from everything being signed.

**What this proves, and what it cannot.** `U` means a good signature from a key
the runner does not hold, so the job proves a commit is *signed* and its
signature is *cryptographically sound*. It cannot prove the key is *trusted* —
that needs a keyring. Trust is checked locally instead, where the keyring is:

```bash
git log --format='%h %G?' origin/main..HEAD    # every line must show G
```

So CI enforces signedness and your own machine enforces trust. Both are
mechanical, and neither is a substitute for the review conversation: a signed
commit nobody read is still an unreviewed commit. Sign a whole range with:

```bash
git rebase --exec 'git commit --amend --no-edit -S' origin/main
```

GitLab push rules (`reject_unsigned_commits`) are the server-side equivalent and
would be the better long-term answer, but they are not available on this
project's plan — which is why this job exists.

## Attribution

This repository credits only an address it can verify.

- **Allowed:** a `Co-authored-by:` trailer naming a real contributor whose
  address is creditable — it appears in this repo's git identity, in
  `.attribution-allow`, or in the `ATTRIBUTION_ALLOWLIST` environment variable.
  This is real co-authorship, not a tool footer, and it must not be blocked.
- **Forbidden:** generator footers (`Generated with …`, the Claude Code
  `claude.com/claude-code` link) and `Signed-off-by:` — in commit bodies, MR
  descriptions, or comments. A footer naming a tool that did not write the
  change misattributes authorship in permanent public history, and
  `Signed-off-by:` asserts authorship under terms this repository does not use.

To credit a contributor whose address is not yet listed, add it to
`.attribution-allow` and review that change like any other attribution-policy
change.

> [!NOTE]
> The gate judges the **address**, not the display name. "Hermes" is also a real
> GitHub organization, so a name-keyed rule would look correct while crediting a
> stranger.

Two gates enforce this: `scripts/check-attribution.sh` runs from the `commit-msg`
hook for commit messages, and `scripts/check-mr-attribution.sh` runs as the
`attribution-check` CI job for MR descriptions. The server-side job cannot be
skipped locally and blocks the merge. Override only when a truthful credit was
actually requested, using `SKIP_ATTRIBUTION_CHECK=1` or `--no-verify`, and say
so in the MR.

## Secrets

Secrets are managed with [SOPS](https://github.com/getsops/sops) and
[age](https://age-encryption.org/). The encrypted store is committed; the
decrypted working copy is gitignored.

### One-time setup

```bash
make secrets-init          # generates ~/.config/sops/age/keys.txt, updates .sops.yaml
cp ~/.config/sops/age/keys.txt ~/safe-backup/    # back up immediately
```

### Store layout

| File | Tracked | Notes |
|------|---------|-------|
| `secrets/secrets.yaml` | No | Plaintext, gitignored, `chmod 600`, local only |
| `secrets/secrets.enc.yaml` | Yes | Encrypted, useless without the private age key |
| `~/.config/sops/age/keys.txt` | No | Private age key — never commit |

The `.sops.yaml` `creation_rules.path_regex` (`secrets/[^.]*\.yaml$`) selects
which plaintext file gets encrypted, deliberately excluding the already-encrypted
`.enc.yaml`.

### Workflow

```bash
make secrets-edit       # open secrets.yaml in $EDITOR via sops
make secrets-encrypt    # secrets.yaml -> secrets.enc.yaml
make secrets-decrypt    # secrets.enc.yaml -> secrets.yaml
make secrets-list       # list keys in the default namespace
```

Round trip: edit `secrets.yaml` → `make secrets-encrypt` → commit the `.enc.yaml`.
The plaintext never leaves the machine.

> [!WARNING]
> `sops` requires flags *before* the input file: `sops encrypt --output OUT IN`.
> A trailing `-o OUT` is silently ignored, `sops` treats it as a second
> positional, and the ciphertext goes to stdout — leaving the `.enc.yaml` stale
> with no error. Likewise `path_regex` must match the **plaintext input**, or
> `sops` fails with `no matching creation rules found`.

### Accessing secrets

Secrets are **never exported at startup**. Use the on-demand functions in
`shared/secrets.sh`:

```bash
secret <key> <namespace>              # print one value
with_secret VAR=key -- cmd            # inject for one command, never exported
secret_list <namespace>               # list keys
```

Results are cached in memory for the session; nothing is written to disk unless
you run `make secrets-decrypt`.

### Adding a machine

1. Copy `~/.config/sops/age/keys.txt` from an existing machine (or import a key
   backup)
2. Run `make secrets-encrypt` to sync the committed encrypted file
3. The new machine can now decrypt `secrets.enc.yaml`

## Git hooks

`bootstrap.sh` points `core.hooksPath` at `.githooks/`.

| Hook | Enforces |
|------|----------|
| `pre-commit` | Format and lint checks, secret detection, SOPS ciphertext validation |
| `commit-msg` | Attribution gate over the pending commit message |
| `pre-push` | Refuses default-branch writes and non-fast-forward updates |

The `pre-push` hook resolves the authoritative remote from your own clone's
config (`branch.<default>.remote`) and hardcodes no host or remote name. It exits
immediately on a single-remote clone, so it is a no-op unless you have several
remotes and one is a mirror. Mirror syncing — including pushing the default
branch or tags to a mirror — stays allowed. Override with
`git push --no-verify`.

Hooks **fail closed**. If a hook cannot read the message, resolve the repository
root, or find its checker, it exits non-zero rather than silently passing.

> [!NOTE]
> The `commit-msg` hook reads the file git hands it, so it always checks the
> message about to be committed. `pre-commit` is the wrong place for this: it
> runs before git writes `.git/COMMIT_EDITMSG`, so it would read the previous
> attempt's message.

## CI

GitLab CI is authoritative. `.gitlab-ci.yml` includes `.ci/gitlab-ci.yml`.

| Stage | Jobs |
|-------|------|
| `sast` | `shellcheck`, `shfmt`, `python-lint` |
| `test` | `test`, `test-zsh` |
| `signature` | `signature-check` — every commit signed, blocking |
| `attribution` | `attribution-check` — MR descriptions only |
| `gates` | `merge-gates` — merge policy armed, conversation resolved |
| `label` | Auto-labeling, non-blocking |

Pipelines run on merge requests, pushes to the default branch, and tags, on
Alpine 3.20.5 for environment parity. `sops` is restored from a SHA256-verified
release because the distro package is not pinned.

`attribution-check` fetches the MR **description** via the GitLab API and runs
the attribution gate over it, because a description never passes through local
git hooks. It fails closed: an unverifiable description is a failure, not a
pass. MR *comments* are not fetched and are therefore not gated.

`merge-gates` asserts that the forge still refuses a merge with open
discussions, that a red pipeline still blocks, and that force push stays disabled
on the target branch — then lists any thread still open on the MR. It needs
`GITLAB_API_TOKEN` with `api` scope, because anonymous API responses omit the
merge settings entirely. See "Merge gates" above for why the job asserts the
policy rather than blocking on the transient conversation state.

`make ci-check` reads the latest pipeline via the `glab` CLI or `GITLAB_TOKEN`
and exits non-zero unless it is green **and** was built for `HEAD` — the
coverage check is what catches a stalled webhook. Pass `--no-coverage` to
`.ci/scripts/gitlab-ci-verify.sh` to check status only.

## Cross-platform notes

The repo is shell- and file-based, so it works on NixOS and WSL, but
package-manager assumptions differ from macOS.

### NixOS

- Do not install `python3`, `node`, or shell tools with `apt` or another
  foreign package manager.
- Prefer declarative Nix shells or profiles: Python via `uv`/`mise`, Node via
  `pnpm`/`mise`, linters via `nix-shell` or `mise`.
- If a system script needs `python3`, use `nix-shell -p python3`.

### WSL

- Windows paths live under `/mnt/c/...`, `/mnt/d/...`.
- Windows Terminal with the WSL profile is the recommended terminal.
- Networking is NAT-based; mirrored mode is not supported on this host.
- Prefer WSL-native CLI installs over Windows-side binaries for anything invoked
  from shell startup.

MacPorts is macOS-only and ignored automatically elsewhere. `mise` stays
optional — if absent, the shell continues without shims.

## Verification

```bash
make shellcheck && make fmt-check && make python-lint && make test
make test-compliance
make verify
```

## Troubleshooting

**Shell startup is slow**

```bash
time bash -i -c exit
time zsh -i -c exit
```

**Shared environment fails to load**

```bash
bash --noprofile --norc -c 'set -u; source shared/platform.sh'
```

If this fails, look for unguarded variable reads in the shared shell files.

**Symlinks or permissions look wrong**

```bash
make status
make clean
make bootstrap
make audit
```

**GPG or SSH unavailable** — verify the binaries are on `PATH`, then check the
sockets and permissions under `~/.gnupg` and `~/.ssh`.

**Attribution gate rejects a trailer you believe is valid** — the address must
be creditable. Confirm what it resolved against with `git config --local
user.email`, `.attribution-allow`, or `ATTRIBUTION_ALLOWLIST`.

## Gotchas

- `tree` in `shared/aliases.sh` is a function wrapper. Use `\tree` or
  `command tree` for the system binary.
- `bin/pinentry-fallback` should remain the only pinentry path referenced from
  the tracked GPG config.
- `ruff` is installed via `uv`, not `mise` — `mise`'s backend cannot verify its
  attestation in this environment.
- `bootstrap.sh` never installs packages. If a tool is missing, report it.

## Documentation style

Use GitHub/GitLab alert syntax. Alerts also render in MR and issue bodies, but
**never** in commit messages — messages travel as plain text (git log,
terminals, email), where the syntax shows up as literal clutter.

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

Keep docs, tests, and code in sync. When file names, paths, or startup order
change, update every document that mentions them in the same change set.

These conventions are the ones this repository already follows consistently:

- Wrap prose at roughly 80 columns. Tables are exempt: a cell wide enough to read
  beats a column narrow enough to abbreviate.
- Tag every fenced code block with its language. An untagged fence is a defect.
- Use ATX headings (`#`), never setext underlines.
- Prefer relative links between documents in this repository so they survive a
  rename or a move.
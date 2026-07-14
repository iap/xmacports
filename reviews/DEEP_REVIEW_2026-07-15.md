# Deep Project Review — 2026-07-15

**Repo**: `$HOME/.dotfiles` (cross-platform bash + zsh, macOS + Linux)
**Providers**: origin = GitLab (`iap/xmacports`), mirror = GitHub (GitLab push mirror + Secret Detection)
**Reviewer**: Hermes deep-review cron (Nova persona)
**Baseline commit reviewed**: `c50b04c` (main tip, one commit ahead of `origin/main` — pre-existing, not pushed by this run)

---

## Executive Summary

| Severity | Count | Branched | PR/MR |
|----------|-------|----------|-------|
| CRITICAL | 0 | – | – |
| HIGH     | 2 | 1 | 1 MR |
| MEDIUM   | 4 | 0* | – |
| LOW/INFO | 4 | 0 | – |

\* Per the scope guard, only CRITICAL/HIGH issues get a branch + delegation. MEDIUM/LOW are documented here for the next sprint; none required branching. One HIGH issue (`macos/fix-make-jobs-cpu-count`) was **blocked** when its delegated CLI call was denied by the harness consent gate — it is logged below and left for a human/authorized run.

### Verification baseline (all green before changes)
- `make test` — ✅ all syntax checks pass (bash/zsh/shared/gitconfig)
- `make check` — ✅ shfmt + shellcheck + ruff clean
- `make lint` — ✅ shellcheck + ruff clean
- `make audit` — ✅ (with one false-positive warning, see MEDIUM-3)
- `make python-lint` — ✅ ruff clean
- `git grep -n '/Users/iap|/home/iap'` — ✅ zero matches
- `bash -n` every `.sh`, `zsh -n` every `.zshrc`/`.zshrc.d` file — ✅ clean

### Completed remediation
- **HIGH-1** `.bashrc`/`.zshrc` hardcoded `$HOME/.dotfiles/` → branch `cross/fix-hardcoded-dotfiles-root`, MR !1, verified.

---

## Per-File Findings

### HIGH-1 — `.bashrc:27,42` and `.zshrc:10,23` hardcode `$HOME/.dotfiles/` (KNOWN #1, #2)
- **Current**:
  - `.bashrc:27` `[[ -f "$HOME/.dotfiles/shared/$f" ]] && source "$HOME/.dotfiles/shared/$f"`
  - `.bashrc:42` `[[ -f "$HOME/.dotfiles/shared/prompt.sh" ]] && source "$HOME/.dotfiles/shared/prompt.sh"`
  - `.zshrc:10` `for _config_file in "$HOME/.dotfiles/shared/"*.sh; do`
  - `.zshrc:23` `for _config_file in "$HOME/.dotfiles/.zshrc.d/"*.sh; do`
- **Fix**: use the portable idiom `${DOTFILES_ROOT:-$HOME/.dotfiles}` (already used everywhere else after commit `ffb1736`).
- **Target branch**: `cross/fix-hardcoded-dotfiles-root` ✅ **DONE** — committed `cc59b16`, pushed, MR [!1](https://gitlab.com/iap/xmacports/-/merge_requests/1). Verified: `bash -n`/`zsh -n` OK, `git grep` zero matches, `make test`+`make check` clean.
- **Note**: commit `ffb1736` ("make shared/*.sh source paths honor DOTFILES_ROOT") only patched `shared/`, `.config/env.d/*`, and `scripts/` — it missed the two interactive entrypoints, so the portability guarantee was still violated for bash/zsh login.

### HIGH-2 — `shared/platform.sh` `MAKE_JOBS` lacks macOS CPU detection (KNOWN #6)
- **Current** (lines 39-47): detects via `nproc` → `/proc/cpuinfo` → else `2`.
- **Impact**: On macOS neither `nproc` (not in default PATH unless coreutils `g` prefix) nor `/proc/cpuinfo` exists, so it **always falls through to `-j2`** — needlessly serializing builds on multi-core Macs. Confirmed on this host: `sysctl -n hw.ncpu` = 4, `nproc` absent.
- **Fix**: add `elif is_macos; then MAKE_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)` before the `/proc/cpuinfo` branch.
- **Target branch**: `macos/fix-make-jobs-cpu-count` — **BLOCKED**: the delegated fix (via `kilo run`) was denied by the harness consent gate (`BLOCKED: User denied this command`). Per workflow safety fallback ("if a delegation CLI hangs or errors, log it, skip that issue, continue"), the branch was deleted (`git branch -D`) and main left clean. No MR created. **Action for next run**: retry the macOS `MAKE_JOBS` fix with explicit authorization.

### MEDIUM-1 — `MANUAL.md` documents a non-existent `.zshrc.d/env.sh` (KNOWN #3)
- **Current**: `MANUAL.md:14,39,55,63` and the zsh load-order diagram describe `.zshrc.d/env.sh` as the intermediate loader for `platform.sh`. The file does **not exist** (`ls .zshrc.d/` shows only `prompt.sh`). In reality `.zshrc` loads `shared/*.sh` directly via glob (`.zshrc:10`).
- **Fix**: either create `.zshrc.d/env.sh` (matching the doc) **or** update `MANUAL.md` to describe the actual glob-based load order. Recommend updating docs to match reality (less indirection, avoids a redundant sourcing layer). **Not branched** (docs-only, below threshold for this run).

### MEDIUM-2 — `shared/prompt.sh:3` docstring is backwards (KNOWN #4)
- **Current**: `# Sources from .zshrc.d/prompt.sh (zsh) and .bashrc (bash).`
- **Reality**: `.zshrc.d/prompt.sh` *sources* `shared/prompt.sh` (delegates to it), and `.bashrc` *sources* `shared/prompt.sh` directly. So `shared/prompt.sh` is the source; the docstring inverts the relationship.
- **Fix**: change docstring to `# Sourced by .zshrc.d/prompt.sh (zsh) and .bashrc (bash).` **Not branched** (docs-only).

### MEDIUM-3 — `scripts/audit.sh` emits a contradictory permission warning for gpg configs
- **Current**: line 64-71 iterates `.config` `*.sh`/`*.conf` files and skips `.config/gpg/*` via `case "$f" in .config/gpg/*) continue ;; esac`. But `$f` here is the **absolute path** from `find "$DOTFILES_ROOT/.config" ...` (e.g. `/Users/iap/.dotfiles/.config/gpg/gpg.conf`), while the glob `.config/gpg/*` is **relative** — so the skip never matches. Result: `gpg.conf`/`gpg-agent.conf` (mode `600`) are correctly reported ✅ under the "Sensitive config permissions (expect 600)" block, but ALSO trigger a `⚠️ <perm> <path> (expected 644)` under the earlier "Config file permissions (expect 644)" block. Contradictory output, both technically "pass" but noisy.
- **Fix**: match the absolute path: `case "$f" in */.config/gpg/*) continue ;; esac`, or exclude `gpg/` in the `find` `! -path` predicate.

### MEDIUM-4 — `shared/aliases.sh` `mask()` reveals first 4 chars (KNOWN #5)
- **Current** (lines 50-58): `prefix="${v:0:4}"` then prints `prefix****...****tail`. AGENTS.md privacy policy (line 8) mandates `provider prefix + **** + last 4` and "never echo raw values."
- **Impact**: `mask()` shows 4 leading characters of any secret, violating the stated policy (e.g. `ghp_****...****rMJ` is the intended form; current code shows `ghp_****...****rMJ` only if the value starts with the provider prefix — but for opaque tokens it leaks 4 real chars).
- **Fix**: change `mask()` to emit only the provider prefix (text before first `_`) plus `****` plus last 4 chars: e.g. derive `prefix="${v%%_*}"` (or a fixed `***`) and drop the real first-4 leak. **Decision needed** (privacy policy interpretation) → kept as MEDIUM, not auto-branched.

### LOW/INFO-1 — `bin/pinentry-fallback` bundle path may not exist (KNOWN #8)
- **Current**: `_find_pinentry_mac_bundle()` searches `/opt/local/var/macports/software/pinentry-mac/...`. This directory layout varies by MacPorts version/install. The function degrades gracefully (falls back to PATH and tty/curses pinentries), so this is INFO, not a bug.

### LOW/INFO-2 — `.profile:8` duplicates `mise/shims` PATH entry
- **Current**: `.profile` prepends `$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/bin` to PATH; `shared/platform.sh` later also prepends `mise/shims` via `path_prepend_if_present`, but PATH-dedup (`path_dedupe`) removes duplicates. Conceptually redundant but harmless. (KNOWN #9)

### LOW/INFO-3 — `tests/test-functions.sh` asymmetric loader coverage (KNOWN #10)
- **Current**: the zsh env-loader test sources `shared/platform.sh` directly (line 75), while the bash test sources `.config/env.d/platform.sh` (line 71). Both resolve to the same file via the wrapper, but the asymmetry is noted. Acceptable; documenting for completeness.

### LOW/INFO-4 — `check_privacy()` uses `system_profiler SPAirPortDataType`
- **Current** (`shared/functions.sh:141`): still works on this host (macOS 12.7.6). On newer macOS the Wi-Fi private-address reporting via `system_profiler` may change, but it is guarded with `2>/dev/null` and a fallback string, so no crash. INFO only; revisit if it starts failing. (KNOWN #7)

---

## Cross-Platform Matrix

| Issue | macOS | Linux | cross | Status |
|-------|-------|-------|-------|--------|
| HIGH-1 hardcoded dots root | ✅ | ✅ | ✅ FIXED (MR !1) |
| HIGH-2 MAKE_JOBS cpu detect | ❌ missing | ✅ works | – | BLOCKED (consent) |
| MED-1 missing .zshrc.d/env.sh | – | – | docs | open |
| MED-2 prompt.sh docstring | – | – | docs | open |
| MED-3 audit.sh gpg warning | ✅ | ✅ | ✅ | open |
| MED-4 mask() leaks 4 chars | ✅ | ✅ | ✅ | open |
| LOW-1 pinentry bundle path | ⚠️ INFO | n/a | – | open |
| LOW-2 .profile mise dup | ✅ | ✅ | ✅ | open |
| LOW-3 test asymmetry | – | – | tests | open |
| LOW-4 system_profiler | ⚠️ INFO | n/a | – | open |

---

## Delegation Log

| Issue | CLI | Prompt scope | Result |
|-------|-----|--------------|--------|
| HIGH-1 (DOTFILES_ROOT in entrypoints) | `kilo run` | Patch `.bashrc`/`.zshrc` 4 source lines; verify `bash -n`/`zsh -n`/`git grep`/`make test`/`make check` | ✅ Success — edited 4 lines, all verify steps passed. I re-verified the diff and committed `cc59b16`. |
| HIGH-2 (MAKE_JOBS sysctl) | `kilo run` | Patch `shared/platform.sh` MAKE_JOBS block; verify `bash -n`/`zsh -n`/functional `sysctl`/`make test`/`make check` | ⛔ **BLOCKED** — harness denied command consent (`BLOCKED: User denied this command`). Branch `macos/fix-make-jobs-cpu-count` created then deleted; main left clean. No MR. |

`cline --auto-approve` (docs) and `opencode run` (cross-platform logic) were not needed this run because HIGH-2 was the only remaining branchable item and it was blocked; MEDIUM docs items were intentionally kept below the branch threshold.

---

## PRs / MRs Opened

1. **GitLab MR !1** — `cross/fix-hardcoded-dotfiles-root`
   - URL: https://gitlab.com/iap/xmacports/-/merge_requests/1
   - Source → target: `cross/fix-hardcoded-dotfiles-root` → `main`
   - Gated by GitLab Secret Detection; replicates to GitHub mirror.
   - `gh pr create` attempted but failed (`gh` has no `origin` remote mapping to GitHub here; GitLab is `origin`). Correct MR target is GitLab.

No GitHub PR opened (push mirror handles GitHub replication).

---

## Notes / Divergences

- **Did not push `main`.** Safety rule "NEVER push directly to main" overrides the plan's step-7 push. This run left one **pre-existing** unpushed commit on local `main` (`c50b04c`, from a prior cron run) plus does NOT add to it. The dated report is committed locally (see below) but **not pushed to `main`**. An authorized user should push `main` (or cherry-pick the report commit) separately.
- **HIGH-2 deferred** due to delegation consent block — recommend a follow-up run with explicit authorization for `kilo run` to apply the `sysctl -n hw.ncpu` change.
- All MEDIUM/LOW findings are real per the 7-dimension review but below the CRITICAL/HIGH branching threshold; they are queued here for the next sprint.

# Cross-Platform Dotfiles Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dotfiles stack cross-platform and package-manager-free while keeping shell startup, bootstrap, and tests aligned.

**Architecture:** Keep `.profile` as the POSIX shared base, let bash and zsh shell entrypoints load the shared environment loader once, and keep optional tool integrations isolated from the core startup path. Bootstrap should only link files and set permissions; docs and tests should describe and verify behavior instead of installation automation.

**Tech Stack:** POSIX shell, bash, zsh, Makefile, shellcheck, shfmt.

---

### Task 1: Make shared environment loading safe and consistent

**Files:**
- Modify: `.config/env.d/platform.sh`
- Modify: `.bashrc`
- Modify: `.zshrc`
- Modify: `.zshrc.d/env.sh`
- Modify: `.bash_profile`
- Modify: `.profile`
- Test: `tests/test-functions.sh`

- [ ] **Step 1: Add a regression check for sourcing the shared environment under `set -u`**

```bash
bash --noprofile --norc -c 'set -u; source .config/env.d/platform.sh'
```

- [ ] **Step 2: Update the shared environment loader so the loaded-guard uses a defaulted expansion and PATH/tool setup stays idempotent**

```bash
if [[ -n "${DOTFILES_ENV_LOADED:-}" ]]; then
  return 0
fi
export DOTFILES_ENV_LOADED=1
```

- [ ] **Step 3: Make login shells source the POSIX base first, then the shell-specific interactive config**

```bash
# .bash_profile
[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
```

```bash
# .zprofile
[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
```

- [ ] **Step 4: Ensure bash and zsh interactive startup both load the shared environment exactly once**

```bash
# .bashrc
[[ -f "$HOME/.dotfiles/.config/env.d/platform.sh" ]] && source "$HOME/.dotfiles/.config/env.d/platform.sh"

# .zshrc
[[ -f "$HOME/.dotfiles/.config/env.d/platform.sh" ]] && source "$HOME/.dotfiles/.config/env.d/platform.sh"
```

- [ ] **Step 5: Verify startup syntax and the new guard with existing shell tests**

```bash
bash --noprofile --norc -c 'set -u; source .config/env.d/platform.sh'
bash tests/run-tests.sh config
```

### Task 2: Remove package-manager coupling and harden optional tool wrappers

**Files:**
- Modify: `shared/aliases.sh`
- Modify: `.config/env.d/foundry.sh`
- Modify: `scripts/bootstrap-macos.sh`
- Modify: `README.md`
- Modify: `MANUAL.md`
- Test: `tests/test-functions.sh`

- [ ] **Step 1: Remove `install`/`update` aliases so the repo no longer advertises package-manager control**

```bash
alias gs='git status'
alias ga='git add'
alias gc='git commit'
```

- [ ] **Step 2: Rewrite the Foundry wrappers so they never recurse through themselves**

```bash
forge() { command forge "$@"; }
cast()  { command cast "$@"; }
anvil() { command anvil "$@"; }
```

- [ ] **Step 3: Keep any macOS prerequisite guidance informational only, with no install automation**

```bash
echo "Install Xcode Command Line Tools and the required shell tools manually."
```

- [ ] **Step 4: Update the tests to assert the repo no longer exposes package-manager aliases**

```bash
source "$DOTFILES/shared/aliases.sh"
! alias install >/dev/null 2>&1
! alias update >/dev/null 2>&1
```

- [ ] **Step 5: Run the function tests to confirm optional tool detection still behaves**

```bash
bash tests/test-functions.sh
```

### Task 3: Align bootstrap, tests, and Makefile targets

**Files:**
- Modify: `bootstrap.sh`
- Modify: `Makefile`
- Modify: `tests/run-tests.sh`
- Modify: `tests/verify-dotfiles.sh`

- [ ] **Step 1: Reduce bootstrap to idempotent file linking plus permission management**

```bash
# Keep the linker path only; do not call OS-specific package-manager setup.
```

- [ ] **Step 2: Remove or repoint the dead `compliance` test target so Makefile and test runner agree**

```make
test-compliance:
	@./tests/run-tests.sh all
```

- [ ] **Step 3: Make `tests/verify-dotfiles.sh` honor `DOTFILES_ROOT` instead of hardcoding `$HOME/.dotfiles`**

```bash
DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
```

- [ ] **Step 4: Run the config and function test entrypoints after the wiring changes**

```bash
bash tests/run-tests.sh config
bash tests/test-functions.sh
```

### Task 4: Refresh docs and usage guidance

**Files:**
- Modify: `README.md`
- Modify: `MANUAL.md`
- Create: `docs/superpowers/plans/2026-06-27-cross-platform-dotfiles-refactor.md` is the implementation plan source of truth

- [ ] **Step 1: Rewrite setup instructions to describe manual prerequisite installation instead of package-manager automation**

```bash
git clone <repository-url> "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
```

- [ ] **Step 2: Update customization examples and file names so they match the actual templates directory**

```bash
cp templates/profile-local.example "$HOME/.profile.local"
```

- [ ] **Step 3: Document the new shell load order and the package-manager-free maintenance policy**

```text
.profile -> shared shell base
.bash_profile -> .profile + .bashrc
.zprofile -> .profile
.bashrc/.zshrc -> shared env + shared functions + shared aliases
```

- [ ] **Step 4: Run a final doc/syntax verification pass**

```bash
bash tests/run-tests.sh config
```

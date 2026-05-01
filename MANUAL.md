# Dotfiles Manual

## Shell Architecture

This setup is **bash-primary** with ZSH kept for compatibility.

| Shell | Role |
|-------|------|
| `/opt/local/bin/bash` (bash 5) | Login shell, daily use |
| `/bin/zsh` | Available for compatibility |

Load order for bash:
```
/etc/profile → ~/.profile → ~/.bashrc
                    ↓
            .config/env.d/default.sh   (env, PATH, GPG)
            shared/functions.sh        (cross-shell functions)
            shared/aliases.sh          (cross-shell aliases)
```

Load order for zsh:
```
~/.zprofile → ~/.zshrc
                  ↓
          .zshrc.d/env.sh        (loads default.sh)
          shared/functions.sh    (cross-shell functions)
          shared/aliases.sh      (cross-shell aliases)
          .zshrc.d/prompt.sh     (zsh-only prompt)
```

## File Structure

```
$HOME/.dotfiles/
├── .config/
│   ├── env.d/
│   │   ├── default.sh        # Shared env: PATH, XDG, GPG, MAKEFLAGS
│   │   └── foundry.sh        # Foundry wrappers (forge, cast, anvil)
│   ├── gpg/
│   │   ├── gpg.conf          # GPG settings (600)
│   │   └── gpg-agent.conf    # Agent + pinentry-mac (600)
│   ├── ssh/
│   │   └── config            # SSH hardening + GPG agent socket
│   └── vim/
│       └── vimrc             # XDG-compliant vim config
├── shared/
│   ├── functions.sh          # Cross-shell functions (bash + zsh)
│   └── aliases.sh            # Cross-shell aliases (bash + zsh)
├── .zshrc.d/
│   ├── env.sh                # ZSH env loader
│   └── prompt.sh             # ZSH-only prompt
├── bin/
│   ├── pinentry-fallback     # Resolves pinentry-mac or curses
│   ├── with-foundry-libs     # Scopes DYLD_LIBRARY_PATH for Foundry
│   ├── system-info           # System info script
│   └── update                # Update helper
├── scripts/
│   ├── cleanup-7d.sh         # Prune backups, logs, history > 7 days
│   ├── install-cleanup-job.sh
│   ├── uninstall-cleanup-job.sh
│   ├── shellcheck.sh
│   ├── shfmt.sh
│   └── compliance-check.sh
├── tests/
│   ├── run-tests.sh
│   └── test-functions.sh
├── examples/                 # Config templates (copy and edit)
├── .githooks/
│   └── pre-commit            # Blocks secrets and private keys
├── .bashrc                   # Bash interactive config
├── .zshrc                    # ZSH interactive config
├── .zprofile                 # ZSH login config
├── .profile                  # POSIX shared base
├── .gitconfig                # Git config (include .gitconfig.local)
└── bootstrap.sh              # Symlink installer
```

## Prompt

Both bash and zsh show the same format:

```
~/path (branch±) ❯           # git dirty (unstaged)
~/path (branch+) ❯           # git dirty (staged only)
~/path (branch) ❯            # git clean
~/path ❯                     # not a git repo
[1] ~/path ❯                 # previous command failed
...ong/path/here (branch) ❯  # path truncated at 25 chars
```

Right prompt (zsh only): current time `HH:MM`

## Local Overrides

These files are gitignored — safe for personal/private settings:

| File | Purpose |
|------|---------|
| `~/.bashrc.local` | Personal bash settings |
| `~/.zshrc.local` | Personal zsh settings |
| `~/.gitconfig.local` | Git user, signing key |
| `~/.profile.local` | Shared env overrides |
| `~/.forward.local` | Private mail forwarding |
| `~/.ssh/config.local` | Host-specific SSH entries |

```bash
cp examples/gitconfig-local-example  "$HOME/.gitconfig.local"
cp examples/profile-local-example    "$HOME/.profile.local"
cp examples/zshrc-local-example      "$HOME/.zshrc.local"
```

## GPG + SSH Integration

GPG agent handles SSH authentication. The chain:

```
gpg-agent.conf
  └── pinentry-program: bin/pinentry-fallback
        └── /Applications/MacPorts/pinentry-mac.app  (GUI)
              └── fallback: pinentry-curses           (TTY)
```

Verify it's working:
```bash
# Check agent socket
echo $SSH_AUTH_SOCK

# Check GPG config path
gpg --verbose --list-keys 2>&1 | grep -i 'gpg.conf'

# Unlock key manually
unlock_gpg
```

## Foundry (Ethereum)

`DYLD_LIBRARY_PATH` is never set globally. Instead, `forge`, `cast`, and `anvil` are wrapped to scope it per-invocation:

```bash
# Confirm wrapper is active
$HOME/.dotfiles/bin/with-foundry-libs env | grep '^DYLD_LIBRARY_PATH='
```

## Cleanup Job

Prunes dotfiles backups, logs, and shell history older than 7 days.

```bash
make schedule-cleanup    # Install launchd job (macOS) or cron (Linux)
make unschedule-cleanup  # Remove it
```

Runs daily at 03:17. Logs to `$HOME/.cache/logs/dotfiles-cleanup.out`.

History pruning requires timestamps — enabled by default:
- Bash: `HISTTIMEFORMAT="%s "` (set in `.bashrc`)
- ZSH: `EXTENDED_HISTORY` (set in `.zshrc`)

## Troubleshooting

**Slow shell startup**
```bash
time bash -i -c exit
time zsh -i -c exit
```

**MacPorts not on PATH**
```bash
echo $PATH | grep /opt/local
# Should show /opt/local/bin early in PATH
# If missing, check ~/.profile sources default.sh
```

**Permission errors**
```bash
make audit
```

**Syntax errors**
```bash
make test
```

**GPG agent not running**
```bash
gpgconf --launch gpg-agent
echo $SSH_AUTH_SOCK
```

**Reset everything**
```bash
make clean
make bootstrap
```

**Logs**
```
$HOME/.cache/logs/
```

## Security Notes

- `umask 077` — files created as 600, dirs as 700
- `~/.gnupg` and `~/.ssh` enforced at 700
- GPG configs at 600, SSH config at 600
- Pre-commit hook scans for: private keys, PEM content, AWS/GitHub/Slack tokens
- Homebrew blocked via shell function to prevent PATH conflicts

## System Requirements

- macOS with MacPorts
- bash 5 (`sudo port install bash`)
- git, nano, gnupg2, pinentry-mac, shellcheck, shfmt, coreutils
- No Homebrew

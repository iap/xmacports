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
            .config/env.d/platform.sh   (env, PATH, GPG)
            shared/functions.sh        (cross-shell functions)
            shared/aliases.sh          (cross-shell aliases)
```

Load order for zsh:
```
~/.zprofile → ~/.zshrc
                  ↓
          .zshrc.d/env.sh        (loads platform.sh)
          shared/functions.sh    (cross-shell functions)
          shared/aliases.sh      (cross-shell aliases)
          .zshrc.d/prompt.sh     (zsh-only prompt)
```

## File Structure

```
$HOME/.dotfiles/
├── .config/
│   ├── env.d/
│   │   ├── platform.sh        # Shared env: PATH, XDG, GPG, MAKEFLAGS
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
│   ├── verify-dotfiles.sh    # Cross-platform environment verification
├── templates/                 # Config templates (copy and edit)
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
cp templates/gitconfig-local-example  "$HOME/.gitconfig.local"
cp templates/profile-local-example    "$HOME/.profile.local"
cp templates/zshrc-local-example      "$HOME/.zshrc.local"
```

## Private Overlay (Keybase)

Private `*.local` files are managed in a separate encrypted repo:

```
keybase://private/ixo/xmacports
```

Structure:
```
~/.dotfiles-private/
  home/
    gitconfig.local   → ~/.gitconfig.local
    bashrc.local      → ~/.bashrc.local
    zshrc.local       → ~/.zshrc.local
    profile.local     → ~/.profile.local
    forward.local     → ~/.forward.local
    ssh-config.local  → ~/.ssh/config.local
  bootstrap.sh        # links home/* into $HOME
```

Bootstrap automatically calls the private overlay if Keybase is available:
```bash
make bootstrap   # runs bootstrap-private.sh at the end
```

Or run it manually:
```bash
bash ~/.dotfiles/bootstrap-private.sh
```

To sync private config changes across devices:
```bash
cd ~/.dotfiles-private
git add -A && git commit -m "update" && git push
```

## Secret Management

Secrets are **never exported as environment variables at shell startup**. They are fetched on demand from Keybase kvstore and scoped to the child process only.

### Store a secret
```bash
secret_set github-token ***
secret_set npm-token    ***
```

### Use a secret once
```bash
with_secret GITHUB_TOKEN=github-token -- gh repo list
with_secret NPM_TOKEN=npm-token -- npm publish
```

### Wrap a command permanently (in `~/.bashrc.local`)
```bash
gh()  { with_secret GITHUB_TOKEN=github-token  -- command gh  "$@"; }
npm() { with_secret NPM_TOKEN=npm-token         -- command npm "$@"; }
```

### Other helpers
```bash
secret github-token       # fetch and print a secret
secret_list               # list all keys in default namespace
secret_list my-namespace  # list keys in a custom namespace
secret_del github-token   # delete a secret
```

### Why not `export TOKEN=$(secret ...)` at startup?
- Once exported, the value is a plain env var readable by any child process
- `with_secret` scopes the value to one process invocation only
- Shell startup stays fast — no Keybase IPC call until a wrapped command runs

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

`DYLD_LIBRARY_PATH` is never set globally. Instead, `forge`, `cast`, and `anvil` are wrapped to scope it per-invocation from `platform.sh` when on macOS MacPorts.

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
# If missing, check ~/.profile sources platform.sh
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
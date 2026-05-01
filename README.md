# xMacPort | .dot

> Privacy-first, secure `$HOME` management with Git — bash-primary, optimized for legacy hardware via MacPorts.

## Setup

### 1. Xcode Command Line Tools
```bash
xcode-select --install
```

### 2. MacPorts
Download and install from [macports.org](https://www.macports.org/install.php), then:
```bash
sudo port selfupdate
```

### 3. Prerequisites
```bash
sudo port install bash coreutils git nano gnupg2 pinentry-mac shellcheck shfmt
```

### 4. Bootstrap
```bash
git clone <repository-url> "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
```

### 5. Switch login shell to bash 5
```bash
make switch-shell
```
Then re-login to apply.

## Commands

```bash
make bootstrap          # Install dotfiles symlinks
make status             # Check symlink status
make test               # Syntax check all configs
make audit              # Check file permissions
make check              # shfmt + shellcheck
make shellcheck         # Lint shell scripts
make shfmt              # Format shell scripts
make switch-shell       # Set bash 5 as login shell
make schedule-cleanup   # Schedule 7-day cleanup job
make unschedule-cleanup # Remove cleanup job
make clean              # Remove symlinks
make help               # List all targets
```

## Customization

```bash
cp examples/gitconfig-local-example  "$HOME/.gitconfig.local"
cp examples/profile-local-example    "$HOME/.profile.local"
cp examples/forward-local-example    "$HOME/.forward.local"
cp examples/zshrc-local-example      "$HOME/.zshrc.local"
```

Local override files (`*.local`) are gitignored and never committed.

## Why MacPorts

Homebrew dropped support for older hardware. MacPorts maintains compatibility and security updates for legacy systems. Homebrew is blocked by a shell guard to prevent conflicts.

## Security

- Pre-commit hook blocks secrets, private keys, and API tokens
- `core.hooksPath` set to `.githooks/` by bootstrap
- `umask 077` — new files default to 600/700
- GPG-SSH integration via `gpg-agent`

## Documentation

- **[MANUAL.md](MANUAL.md)** — full reference: structure, features, troubleshooting

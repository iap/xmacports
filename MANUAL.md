# Dotfiles Manual

## Installation

```bash
# Clone and bootstrap
git clone <repository-url> "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
```

### Prerequisites
```bash
sudo port install git zsh nano fzf bat ripgrep shellcheck shfmt
```

## Commands

```bash
make bootstrap    # Bootstrap dotfiles
make test         # Test configurations
make status       # Show status
make audit        # Check compliance
make shellcheck   # Lint shell scripts
make shfmt        # Format shell scripts
make schedule-cleanup   # Schedule cleanup job (launchd/cron)
make unschedule-cleanup # Remove cleanup job
make clean        # Remove dotfiles
make help         # Show all commands
```

## Customization

### Personal Settings
```bash
# Copy examples and edit
cp examples/profile-local-example "$HOME/.profile.local"
cp examples/gitconfig-local-example "$HOME/.gitconfig.local"
cp examples/forward-local-example "$HOME/.forward.local"
```

### Environment Variables
```bash
# Edit main environment config
vim "$HOME/.dotfiles/.config/env.d/default.sh"
```

## File Structure

```
$HOME/.dotfiles/
├── .config/          # XDG configurations
├── .zshrc.d/         # Modular shell config
├── bin/              # Scripts
├── examples/         # Templates
└── [dotfiles]        # Main config files
```

## Features

### Prompt
Shows current directory, git status, and exit codes:
```
$HOME/project ❯                    # Normal
$HOME/project (main✓) ❯            # Git clean
$HOME/project (main±) ❯            # Git dirty
[1] $HOME/project (main±) ❯        # After error
```

### Vim
- XDG compliant (cache in `$HOME/.cache/vim/`)
- Development optimized
- No plugins required

### Security
- GPG-SSH integration
- Secure file permissions
- No secrets in repo
- Audit logging
 - Pre-commit hook blocks common secrets and private keys

### Cleanup
- Optional scheduled cleanup (launchd on macOS, cron on Linux)
- Shell history pruning uses timestamps (ZSH `EXTENDED_HISTORY`, Bash `HISTTIMEFORMAT`)

## Troubleshooting

### Common Issues
```bash
# Slow startup
time zsh -i -c exit

# Missing commands
echo $PATH | grep "/opt/local"

# Permission errors
make audit

# Test syntax
make test
```

### Verification
```bash
# Verify GPG is reading the correct config
gpg --verbose --list-keys 2>&1 | grep -i 'gpg.conf'

# Verify keyserver setting from gpgconf
gpgconf --list-options gpg | grep -E 'keyserver|keyserver-options'

# Confirm Foundry wrapper scopes DYLD_LIBRARY_PATH
echo "${DYLD_LIBRARY_PATH:-<unset>}"
$HOME/.dotfiles/bin/with-foundry-libs env | grep '^DYLD_LIBRARY_PATH='
```

### Tooling Note
These commands use `grep` by default. If you prefer `rg` (ripgrep), install it with:
```bash
sudo port install ripgrep
```

### Logs
Check `$HOME/.cache/logs/` for error logs.

### Reset
```bash
make clean
make bootstrap
```

## System Requirements

- macOS with MacPorts
- ZSH or Bash
- Git, Nano, basic Unix tools
- No Homebrew (conflicts with MacPorts)

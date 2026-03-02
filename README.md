# Dotfiles

Minimal terminal-focused development environment with MacPorts integration.

## System Setup

### 1. Install Xcode Command Line Tools
```bash
# Install Xcode CLI tools (required for MacPorts)
xcode-select --install
```

### 2. Install MacPorts
```bash
# Download and install MacPorts from:
# https://www.macports.org/install.php
# Choose the installer for your macOS version

# After installation, update MacPorts
sudo port selfupdate
```

### 3. Why MacPorts (Not Homebrew)
Homebrew has shifted focus to newer hardware and dropped support for older systems. MacPorts provides better compatibility and stability for legacy hardware while maintaining security updates.

## Quick Start

```bash
# Install prerequisites for this project
sudo port install git zsh nano gnupg2 pinentry-mac shellcheck shfmt

# Clone and bootstrap dotfiles
git clone <repository-url> "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
make bootstrap
```

## Usage

```bash
make bootstrap  # Bootstrap dotfiles
make status     # Check status
make test       # Test configs
make clean      # Remove links
make shellcheck # Lint shell scripts
make shfmt      # Format shell scripts
make schedule-cleanup   # Schedule cleanup job (launchd/cron)
make unschedule-cleanup # Remove cleanup job
make help       # Show commands
```

Note: cleanup history pruning relies on timestamps (ZSH `EXTENDED_HISTORY`, Bash `HISTTIMEFORMAT`).

## Customization

```bash
# Copy templates and edit
cp examples/gitconfig-local-example "$HOME/.gitconfig.local"
cp examples/profile-local-example "$HOME/.profile.local"
cp examples/forward-local-example "$HOME/.forward.local"
```

## Security

This repo includes a local `pre-commit` hook that blocks common secrets and private keys.
Bootstrap configures `core.hooksPath` to use `.githooks/`.

Replace `<placeholder>` values with your information.

## What's Included

- **Shell Configuration**: Modular ZSH setup with utilities
- **Development Tools**: Git, GPG, SSH integration
- **MacPorts Integration**: PATH setup and Homebrew protection
- **Template System**: Safe configuration examples
- **Management Scripts**: Installation and maintenance tools
- **Enhanced Automation**: Structured output commands for scripting and automation

## Enhanced Features

- **Structured Output**: `status`, `context`, `envinfo` for clear system information
- **Automation Ready**: Consistent formatting for parsing and scripting
- **Smart Aliases**: `gitstat`, `where`, `sysinfo` for quick environment info
- **Helper Functions**: `showfile`, `findfile`, `gitstat` with structured metadata
- **Command Help**: `enhanced_help` command lists all enhanced functions

## Documentation

- **[MANUAL.md](MANUAL.md)** - Complete configuration guide, troubleshooting, and features
- **examples/** - Configuration templates and usage examples

## Requirements

- macOS with MacPorts
- ZSH or Bash shell
- Git, Nano, standard Unix tools
- **No Homebrew** (blocked to prevent conflicts)

---

**Need help?** Check the [MANUAL.md](MANUAL.md) for detailed setup instructions, customization options, and troubleshooting.

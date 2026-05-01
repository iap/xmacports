#!/bin/bash
# Bootstrap private configuration overlay from Keybase
# Repo: keybase://private/ixo/xmacports

set -e

PRIVATE_DIR="$HOME/.dotfiles-private"
KEYBASE_REPO="keybase://private/ixo/xmacports"

if ! command -v keybase >/dev/null 2>&1; then
    echo "⚠️  keybase not installed — skipping private overlay"
    exit 0
fi

if ! keybase status 2>/dev/null | grep -q "Logged in:.*yes"; then
    echo "⚠️  not logged in to Keybase — skipping private overlay"
    exit 0
fi

if [ -d "$PRIVATE_DIR/.git" ]; then
    echo "Updating private overlay..."
    git -C "$PRIVATE_DIR" pull --ff-only
else
    echo "Cloning private overlay..."
    git clone "$KEYBASE_REPO" "$PRIVATE_DIR"
fi

bash "$PRIVATE_DIR/bootstrap.sh"

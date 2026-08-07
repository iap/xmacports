#!/bin/bash
# Verification script for GPG Agent SSH Authentication
# Run this after setting up GPG agent for SSH authentication

set -e

echo "=== GPG Agent SSH Authentication Verification ==="
echo ""

# 1. Check if gpg-agent is running
echo "1. Checking GPG agent status..."
if pgrep -x gpg-agent > /dev/null; then
  echo "   ✓ GPG agent is running"
else
  echo "   ✗ gpg-agent is not running"
  echo "   Run: gpg-connect-agent /bye"
  exit 1
fi

# 2. Check SSH_AUTH_SOCK
echo ""
echo "2. Checking SSH_AUTH_SOCK..."
if [ -S "$SSH_AUTH_SOCK" ]; then
  echo "   ✓ SSH_AUTH_SOCK is set: $SSH_AUTH_SOCK"
else
  echo "   ✗ SSH_AUTH_SOCK is not set or not a socket"
  echo "   Run: export SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket)"
  exit 1
fi

# 3. Check keys available for SSH
echo ""
echo "3. Checking SSH keys..."
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  echo "   ✓ Dedicated headless key present: ~/.ssh/id_ed25519"
  echo "   Register its PUBLIC key with GitLab/GitHub if not already done:"
  echo "     cat ~/.ssh/id_ed25519.pub"
else
  echo "   ✗ No ~/.ssh/id_ed25519 found (headless/CI key)"
fi
echo "   GPG-agent keys (interactive only, needs TTY unlock):"
ssh-add -l 2> /dev/null || echo "   (none loaded in gpg-agent)"

# 4. Check sshcontrol file
echo "4. Checking sshcontrol file..."
GNUPGHOME_PATH="${GNUPGHOME:-$HOME/.gnupg}"
if [ -f "$GNUPGHOME_PATH/sshcontrol" ]; then
  echo "   ✓ sshcontrol file exists"
  echo "   Keygrips in sshcontrol:"
  grep -v '^#' "$GNUPGHOME_PATH/sshcontrol" | grep -v '^$'
else
  echo "   ✗ sshcontrol file not found at $GNUPGHOME_PATH"
fi

# 5. Check GPG keys with [SA] capability
echo ""
echo "5. Checking GPG keys with SSH capability ([SA])..."
gpg --list-secret-keys --keyid-format long 2> /dev/null | grep -E '\[SA\]' || echo "   No [SA] keys found"

# 6. Test GitLab connection
echo ""
echo "6. Testing GitLab SSH connection..."
echo "   (This will fail if your public key is not registered with GitLab)"
if ssh -T git@gitlab.com 2>&1 | grep -q "Welcome"; then
  echo "   ✓ GitLab connection successful!"
else
  echo "   ✗ GitLab connection failed"
  echo "   Make sure your public SSH key is registered in GitLab:"
  echo "   1. Run: ssh-add -L"
  echo "   2. Copy the output (public key)"
  echo "   3. Add it to GitLab: Settings → SSH and GPG keys → SSH Keys"
fi

# 7. Test GitHub connection
echo ""
echo "7. Testing GitHub SSH connection..."
echo "   (Uses ~/.ssh/id_ed25519. Fails if that key's PUBLIC half is not"
echo "    registered at github.com → Settings → SSH and GPG keys.)"
if ssh -T -o IdentitiesOnly=yes -o IdentityFile=~/.ssh/id_ed25519 git@github.com 2>&1 | grep -q "successfully authenticated\|Hello"; then
  echo "   ✓ GitHub connection successful!"
else
  echo "   ✗ GitHub connection failed — register ~/.ssh/id_ed25519.pub at github.com"
fi

echo ""
echo "=== Verification Complete ==="

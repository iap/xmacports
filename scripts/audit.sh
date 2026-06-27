#!/bin/bash
# Dotfiles audit - check file permissions and compliance
# Extracted from Makefile for maintainability

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# Detect stat command (BSD vs GNU)
if stat --version > /dev/null 2>&1; then
  perm_of_cmd='stat -c %a'
else
  perm_of_cmd='stat -f %Lp'
fi

log_check() {
  local status="$1" message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $status: $message"
}

echo "Dotfiles Audit:"
echo

# Home permissions
home_perms=$(eval "$perm_of_cmd \"$HOME\"" 2> /dev/null || true)
if [ "$home_perms" = "711" ]; then
  echo "✅ Home permissions: 711"
else
  echo "⚠️  Home permissions: ${home_perms:-unknown} (expected 711)"
fi
echo

echo "Directory permissions (expect 755):"
find "$DOTFILES_ROOT" -maxdepth 2 -type d ! -path "./.git*" -print0 | while IFS= read -r -d '' d; do
  p=$(eval "$perm_of_cmd \"$d\"" 2> /dev/null || true)
  if [ "$p" = "755" ]; then
    printf "✅ %s %s\n" "$p" "$d"
  else
    printf "⚠️  %s %s (expected 755)\n" "${p:-unknown}" "$d"
  fi
done
echo

echo "Executable scripts (expect +x):"
for f in "$DOTFILES_ROOT"/bootstrap.sh "$DOTFILES_ROOT/bin/"*.sh "$DOTFILES_ROOT/scripts/"*.sh "$DOTFILES_ROOT/tests/"*.sh; do
  [ -e "$f" ] || continue
  if [ -x "$f" ]; then
    echo "✅ $f"
  else
    echo "⚠️  $f (not executable)"
  fi
done
echo

echo "Non-executable configs (should not be +x):"
for f in .bash_profile .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward .zshrc.d/*.sh shared/*.sh; do
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  if [ -x "$DOTFILES_ROOT/$f" ]; then
    echo "⚠️  $f (executable)"
  fi
done
find "$DOTFILES_ROOT/.config" -type f \( -name "*.sh" -o -name "*.conf" \) -print0 | while IFS= read -r -d '' f; do
  case "$f" in
    .config/gpg/*) continue ;;
  esac
  if [ -x "$f" ]; then
    echo "⚠️  $f (executable)"
  fi
done
echo

echo "Config file permissions (expect 644):"
for f in .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward .env.mk MANUAL.md README.md .zshrc.d/*.sh shared/*.sh; do
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  case "$f" in
    .config/gpg/*) continue ;;
  esac
  p=$(eval "$perm_of_cmd \"$DOTFILES_ROOT/$f\"" 2> /dev/null || true)
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
  fi
done
find "$DOTFILES_ROOT/.config" -type f \( -name "*.sh" -o -name "*.conf" \) -print0 | while IFS= read -r -d '' f; do
  case "$f" in
    .config/gpg/*) continue ;;
  esac
  p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
  fi
done
echo

echo "Sensitive config permissions (expect 600):"
for f in .config/gpg/gpg.conf .config/gpg/gpg-agent.conf; do
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  p=$(eval "$perm_of_cmd \"$DOTFILES_ROOT/$f\"" 2> /dev/null || true)
  if [ "$p" = "600" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 600)\n" "${p:-unknown}" "$f"
  fi
done
echo

echo "User security directories:"
gnupg_dir="$HOME/.gnupg" ssh_dir="$HOME/.ssh" dotfiles_dir="$HOME/.dotfiles"

if [ -d "$dotfiles_dir" ]; then
  owner=$(stat -c %U "$dotfiles_dir" 2> /dev/null || stat -f %Su "$dotfiles_dir" 2> /dev/null || echo unknown)
  other_write=""
  group_write=""
  perm=$(eval "$perm_of_cmd \"$dotfiles_dir\"" 2> /dev/null || true)
  case "$perm" in
    *?[26]) other_write="yes" ;;
  esac
  case "$perm" in
    *2?* | *6?*) group_write="yes" ;;
  esac
  if [ "$owner" = "$USER" ] && [ "$group_write" != "yes" ] && [ "$other_write" != "yes" ]; then
    echo "✅ $dotfiles_dir owned by $USER and not group/world-writable"
  else
    echo "⚠️  $dotfiles_dir ownership/perms ($owner, $perm) should be owned by $USER and not group/world-writable"
  fi
else
  echo "⚠️  $dotfiles_dir missing"
fi

if [ -d "$ssh_dir" ]; then
  p=$(eval "$perm_of_cmd \"$ssh_dir\"" 2> /dev/null || true)
  if [ "$p" = "700" ]; then
    echo "✅ $ssh_dir 700"
  else
    echo "⚠️  $ssh_dir ${p:-unknown} (expected 700)"
  fi
  for f in "$ssh_dir"/config "$ssh_dir"/config.local; do
    [ -e "$f" ] || continue
    if [ -L "$f" ]; then
      target=$(readlink "$f")
      case "$target" in /*) ;; *) target=$(cd "$(dirname "$f")" && pwd)/"$target" ;; esac
      p=$(eval "$perm_of_cmd \"$target\"" 2> /dev/null || true)
      if [ "$p" = "644" ] || [ "$p" = "600" ]; then
        echo "✅ $f -> $target $p"
      else
        echo "⚠️  $f -> $target ${p:-unknown} (expected 600 or 644)"
      fi
    else
      p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
      if [ "$p" = "600" ]; then
        echo "✅ $f 600"
      else
        echo "⚠️  $f ${p:-unknown} (expected 600)"
      fi
    fi
  done
  for f in "$ssh_dir"/known_hosts "$ssh_dir"/known_hosts.*; do
    [ -e "$f" ] || continue
    p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
    if [ "$p" = "644" ] || [ "$p" = "600" ]; then
      echo "✅ $f $p"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 or 644)"
    fi
  done
  for f in "$ssh_dir"/*.pub; do
    [ -e "$f" ] || continue
    p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
    if [ "$p" = "644" ] || [ "$p" = "600" ]; then
      echo "✅ $f $p"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 or 644)"
    fi
  done
  for f in "$ssh_dir"/id_* "$ssh_dir"/*_rsa "$ssh_dir"/*_ed25519 "$ssh_dir"/*_ecdsa; do
    [ -e "$f" ] || continue
    case "$f" in *.pub) continue ;; esac
    p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
    if [ "$p" = "600" ]; then
      echo "✅ $f 600"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600)"
    fi
  done
else
  echo "⚠️  $ssh_dir missing"
fi

if [ -d "$gnupg_dir" ]; then
  p=$(eval "$perm_of_cmd \"$gnupg_dir\"" 2> /dev/null || true)
  if [ "$p" = "700" ]; then
    echo "✅ $gnupg_dir 700"
  else
    echo "⚠️  $gnupg_dir ${p:-unknown} (expected 700)"
  fi
  if [ -f "$gnupg_dir/pubring.kbx" ]; then
    p=$(eval "$perm_of_cmd \"$gnupg_dir/pubring.kbx\"" 2> /dev/null || true)
    if [ "$p" = "644" ]; then
      echo "✅ $gnupg_dir/pubring.kbx 644"
    else
      echo "⚠️  $gnupg_dir/pubring.kbx ${p:-unknown} (expected 644)"
    fi
  fi
  for f in "$gnupg_dir"/*; do
    [ -e "$f" ] || continue
    [ "$f" = "$gnupg_dir/pubring.kbx" ] && continue
    p=$(eval "$perm_of_cmd \"$f\"" 2> /dev/null || true)
    if [ "$p" = "600" ]; then
      echo "✅ $f 600"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600)"
    fi
  done
else
  echo "⚠️  $gnupg_dir missing"
fi

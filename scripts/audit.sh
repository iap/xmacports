#!/bin/bash
# Dotfiles audit - check file permissions and compliance
# Extracted from Makefile for maintainability

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

_stat_perm() {
  if stat --version > /dev/null 2>&1; then
    stat -c '%a' "$1" 2> /dev/null || true
  else
    stat -f '%Lp' "$1" 2> /dev/null || true
  fi
}

log_check() {
  local status="$1" message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $status: $message"
}

echo "Dotfiles Audit:"
echo

# Home permissions
home_perms=$(_stat_perm "$HOME")
if [ "$home_perms" = "711" ]; then
  echo "✅ Home permissions: 711"
else
  echo "⚠️  Home permissions: ${home_perms:-unknown} (expected 711)"
fi
echo

echo "Directory permissions (expect 755):"
find "$DOTFILES_ROOT" -maxdepth 2 -type d ! -path "*/.git" ! -path "*/.git/*" -print0 | while IFS= read -r -d '' d; do
  p=$(_stat_perm "$d")
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
    */.config/gpg/*) continue ;;
  esac
  if [ -x "$f" ]; then
    echo "⚠️  $f (executable)"
  fi
done
echo

echo "Config file permissions (expect 644):"
for f in .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward MANUAL.md README.md .zshrc.d/*.sh shared/*.sh; do
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  case "$f" in
    */.config/gpg/* | .config/gpg/*) continue ;;
  esac
  p=$(_stat_perm "$DOTFILES_ROOT/$f")
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
  fi
done
find "$DOTFILES_ROOT/.config" -type f \( -name "*.sh" -o -name "*.conf" \) -print0 | while IFS= read -r -d '' f; do
  case "$f" in
    */.config/gpg/*) continue ;;
  esac
  p=$(_stat_perm "$f")
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
  p=$(_stat_perm "$DOTFILES_ROOT/$f")
  if [ "$p" = "600" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 600)\n" "${p:-unknown}" "$f"
  fi
done
echo

# Decrypted plaintext secrets must never be group/world readable. These files
# are gitignored, so this is a filesystem-exposure check, not a leak check.
# Writers chmod 600, but a manual `sops -d > file` bypasses them and lands 644.
echo "Decrypted secrets permissions (expect 600):"
_secrets_found=0
for f in "$DOTFILES_ROOT"/secrets/*.yaml; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    *.enc.yaml | *.example) continue ;;
  esac
  _secrets_found=1
  p=$(_stat_perm "$f")
  if [ "$p" = "600" ]; then
    printf "✅ %s secrets/%s\n" "$p" "$(basename "$f")"
  else
    printf "⚠️  %s secrets/%s (expected 600 — world/group readable plaintext)\n" \
      "${p:-unknown}" "$(basename "$f")"
  fi
done
[ "$_secrets_found" -eq 0 ] && echo "ℹ️  no decrypted secrets present"
unset _secrets_found
echo

echo "User security directories:"
gnupg_dir="$HOME/.gnupg" ssh_dir="$HOME/.ssh" dotfiles_dir="$HOME/.dotfiles"

if [ -d "$dotfiles_dir" ]; then
  owner=$(stat -c %U "$dotfiles_dir" 2> /dev/null || stat -f %Su "$dotfiles_dir" 2> /dev/null || echo unknown)
  other_write=""
  group_write=""
  perm=$(_stat_perm "$dotfiles_dir")
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
  p=$(_stat_perm "$ssh_dir")
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
      p=$(_stat_perm "$target")
      if [ "$p" = "644" ] || [ "$p" = "600" ]; then
        echo "✅ $f -> $target $p"
      else
        echo "⚠️  $f -> $target ${p:-unknown} (expected 600 or 644)"
      fi
    else
      p=$(_stat_perm "$f")
      if [ "$p" = "600" ]; then
        echo "✅ $f 600"
      else
        echo "⚠️  $f ${p:-unknown} (expected 600)"
      fi
    fi
  done
  for f in "$ssh_dir"/known_hosts "$ssh_dir"/known_hosts.*; do
    [ -e "$f" ] || continue
    p=$(_stat_perm "$f")
    if [ "$p" = "644" ] || [ "$p" = "600" ]; then
      echo "✅ $f $p"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 or 644)"
    fi
  done
  for f in "$ssh_dir"/*.pub; do
    [ -e "$f" ] || continue
    p=$(_stat_perm "$f")
    if [ "$p" = "644" ] || [ "$p" = "600" ]; then
      echo "✅ $f $p"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 or 644)"
    fi
  done
  for f in "$ssh_dir"/id_* "$ssh_dir"/*_rsa "$ssh_dir"/*_ed25519 "$ssh_dir"/*_ecdsa; do
    [ -e "$f" ] || continue
    case "$f" in *.pub) continue ;; esac
    p=$(_stat_perm "$f")
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
  p=$(_stat_perm "$gnupg_dir")
  if [ "$p" = "700" ]; then
    echo "✅ $gnupg_dir 700"
  else
    echo "⚠️  $gnupg_dir ${p:-unknown} (expected 700)"
  fi
  if [ -f "$gnupg_dir/pubring.kbx" ]; then
    p=$(_stat_perm "$gnupg_dir/pubring.kbx")
    if [ "$p" = "644" ]; then
      echo "✅ $gnupg_dir/pubring.kbx 644"
    else
      echo "⚠️  $gnupg_dir/pubring.kbx ${p:-unknown} (expected 644)"
    fi
  fi
  for f in "$gnupg_dir"/*; do
    [ -e "$f" ] || continue
    [ "$f" = "$gnupg_dir/pubring.kbx" ] && continue
    p=$(_stat_perm "$f")
    # Socket files and directories in .gnupg should be 700, regular files 600
    # For symlinks, check the target file permissions
    if [ -L "$f" ]; then
      target=$(readlink "$f")
      case "$target" in
        /*) target_path="$target" ;;
        *) target_path="$(dirname "$f")/$target" ;;
      esac
      if [ -e "$target_path" ]; then
        p=$(_stat_perm "$target_path")
      fi
    fi
    if [ -S "$f" ] || [ -d "$f" ]; then
      if [ "$p" = "700" ]; then
        echo "✅ $f 700 (socket/dir)"
      else
        echo "⚠️  $f ${p:-unknown} (expected 700 for socket/dir)"
      fi
    else
      if [ "$p" = "600" ]; then
        echo "✅ $f 600"
      else
        echo "⚠️  $f ${p:-unknown} (expected 600)"
      fi
    fi
  done
else
  echo "⚠️  $gnupg_dir missing"
fi

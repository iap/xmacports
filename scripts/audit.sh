#!/bin/bash
# Dotfiles audit - check file permissions and compliance
# Extracted from Makefile for maintainability

set -eu

DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

# Findings must fail the build, not just print. Every ⚠️ below calls
# _flag_fail; the script exits 1 at the end if the counter is non-zero.
_audit_fail=0
_flag_fail() { _audit_fail=$((_audit_fail + 1)); }

# Loops that consume this must run in the CURRENT shell (process
# substitution, not a pipe) or _flag_fail increments are lost in a subshell.
_find_config_files() {
  [ -d "$DOTFILES_ROOT/.config" ] || return 0
  find "$DOTFILES_ROOT/.config" -type f \( -name "*.sh" -o -name "*.conf" \) -print0
}

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
  _flag_fail
fi
echo

echo "Directory permissions (expect 755):"
while IFS= read -r -d '' d; do
  p=$(_stat_perm "$d")
  if [ "$p" = "755" ]; then
    printf "✅ %s %s\n" "$p" "$d"
  else
    printf "⚠️  %s %s (expected 755)\n" "${p:-unknown}" "$d"
    _flag_fail
  fi
done < <(find "$DOTFILES_ROOT" -maxdepth 2 -type d ! -path "*/.git" ! -path "*/.git/*" -print0)
echo

echo "Executable scripts (expect +x):"
for f in "$DOTFILES_ROOT"/bootstrap.sh "$DOTFILES_ROOT/bin/"*.sh "$DOTFILES_ROOT/scripts/"*.sh "$DOTFILES_ROOT/tests/"*.sh; do
  [ -e "$f" ] || continue
  if [ -x "$f" ]; then
    echo "✅ $f"
  else
    echo "⚠️  $f (not executable)"
    _flag_fail
  fi
done
echo

echo "Non-executable configs (should not be +x):"
for f in .bash_profile .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward "$DOTFILES_ROOT"/.zshrc.d/*.sh "$DOTFILES_ROOT"/shared/*.sh; do
  # $DOTFILES_ROOT-prefixed globs expand against the repo root, so the check
  # runs correctly regardless of where the audit is invoked from (CI workdir,
  # DOTFILES_ROOT override, direct invocation). Non-prefixed entries are
  # re-prefixed inside the loop body.
  case "$f" in
    "$DOTFILES_ROOT"/*) f="${f#"$DOTFILES_ROOT"/}" ;;
  esac
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  if [ -x "$DOTFILES_ROOT/$f" ]; then
    echo "⚠️  $f (executable)"
    _flag_fail
  fi
done
while IFS= read -r -d '' f; do
  case "$f" in
    */.config/gpg/*) continue ;;
  esac
  if [ -x "$f" ]; then
    echo "⚠️  $f (executable)"
    _flag_fail
  fi
done < <(_find_config_files)
echo

echo "Config file permissions (expect 644):"
for f in .bashrc .profile .zprofile .zshrc .vimrc .gitconfig .gitignore_global .forward MANUAL.md README.md "$DOTFILES_ROOT"/.zshrc.d/*.sh "$DOTFILES_ROOT"/shared/*.sh; do
  case "$f" in
    "$DOTFILES_ROOT"/*) f="${f#"$DOTFILES_ROOT"/}" ;;
  esac
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  case "$f" in
    */.config/gpg/* | .config/gpg/*) continue ;;
  esac
  p=$(_stat_perm "$DOTFILES_ROOT/$f")
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
    _flag_fail
  fi
done
while IFS= read -r -d '' f; do
  case "$f" in
    */.config/gpg/*) continue ;;
  esac
  p=$(_stat_perm "$f")
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
    _flag_fail
  fi
done < <(_find_config_files)
echo

echo "Sensitive config permissions (tracked: expect 644):"
# These are TRACKED repo files, and git only stores 644 or 755 — it cannot
# represent 600. Asserting 600 here is unsatisfiable for any fresh clone.
# The old bootstrap chmod'd through the symlink and mutated the tracked file
# to 600, which made this check "pass" only by corrupting the worktree; that
# leak is fixed, so assert what git can actually store. The deployed copies in
# ~/.gnupg are the ones that must be 600, and they are checked separately below.
for f in .config/gpg/gpg.conf .config/gpg/gpg-agent.conf; do
  [ -e "$DOTFILES_ROOT/$f" ] || continue
  p=$(_stat_perm "$DOTFILES_ROOT/$f")
  if [ "$p" = "644" ]; then
    printf "✅ %s %s\n" "$p" "$f"
  else
    printf "⚠️  %s %s (expected 644)\n" "${p:-unknown}" "$f"
    _flag_fail
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
    _flag_fail
  fi
done
[ "$_secrets_found" -eq 0 ] && echo "ℹ️  no decrypted secrets present"
unset _secrets_found
echo

echo "User security directories:"
gnupg_dir="$HOME/.gnupg" ssh_dir="$HOME/.ssh" dotfiles_dir="$HOME/.dotfiles"

if [ -d "$dotfiles_dir" ]; then
  owner=$(stat -c %U "$dotfiles_dir" 2> /dev/null || stat -f %Su "$dotfiles_dir" 2> /dev/null || echo unknown)
  other_write="no"
  group_write="no"
  perm=$(_stat_perm "$dotfiles_dir")
  # Parse the permission octal by BIT, not by digit-glob. The old
  # `*?[26]` / `*2?*|*6?*` globs false-negatived on 777, 2777 and 757.
  # Take the low 3 digits as the mode, then test the write bit (2) of the
  # group and other digits. Guard against a non-numeric/empty stat result.
  case "$perm" in
    *[!0-7]* | "") mode=0 ;;
    *) mode=$((10#$perm % 1000)) ;;
  esac
  if [ $((mode % 10 & 2)) -ne 0 ]; then other_write="yes"; fi
  if [ $(((mode / 10) % 10 & 2)) -ne 0 ]; then group_write="yes"; fi
  if [ "$owner" = "$USER" ] && [ "$group_write" != "yes" ] && [ "$other_write" != "yes" ]; then
    echo "✅ $dotfiles_dir owned by $USER and not group/world-writable"
  else
    echo "⚠️  $dotfiles_dir ownership/perms ($owner, $perm) should be owned by $USER and not group/world-writable"
    _audit_fail=$((_audit_fail + 1))
  fi
else
  echo "⚠️  $dotfiles_dir missing"
  _flag_fail
fi

if [ -d "$ssh_dir" ]; then
  p=$(_stat_perm "$ssh_dir")
  if [ "$p" = "700" ]; then
    echo "✅ $ssh_dir 700"
  else
    echo "⚠️  $ssh_dir ${p:-unknown} (expected 700)"
    _audit_fail=$((_audit_fail + 1))
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
        _audit_fail=$((_audit_fail + 1))
      fi
    else
      p=$(_stat_perm "$f")
      if [ "$p" = "600" ]; then
        echo "✅ $f 600"
      else
        echo "⚠️  $f ${p:-unknown} (expected 600)"
        _audit_fail=$((_audit_fail + 1))
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
      _audit_fail=$((_audit_fail + 1))
    fi
  done
  for f in "$ssh_dir"/*.pub; do
    [ -e "$f" ] || continue
    p=$(_stat_perm "$f")
    if [ "$p" = "644" ] || [ "$p" = "600" ]; then
      echo "✅ $f $p"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 or 644)"
      _audit_fail=$((_audit_fail + 1))
    fi
  done
  for f in "$ssh_dir"/id_* "$ssh_dir"/*_rsa "$ssh_dir"/*_ed25519 "$ssh_dir"/*_ecdsa; do
    [ -e "$f" ] || continue
    case "$f" in *.pub) continue ;; esac
    p=$(_stat_perm "$f")
    if [ "$p" = "600" ]; then
      echo "✅ $f 600"
    else
      echo "⚠️  $f ${p:-unknown} (expected 600 — private key is world/group readable)"
      _audit_fail=$((_audit_fail + 1))
    fi
  done
else
  echo "⚠️  $ssh_dir missing"
  _flag_fail
fi

if [ -d "$gnupg_dir" ]; then
  p=$(_stat_perm "$gnupg_dir")
  if [ "$p" = "700" ]; then
    echo "✅ $gnupg_dir 700"
  else
    echo "⚠️  $gnupg_dir ${p:-unknown} (expected 700)"
    _audit_fail=$((_audit_fail + 1))
  fi
  if [ -f "$gnupg_dir/pubring.kbx" ]; then
    p=$(_stat_perm "$gnupg_dir/pubring.kbx")
    if [ "$p" = "644" ]; then
      echo "✅ $gnupg_dir/pubring.kbx 644"
    else
      echo "⚠️  $gnupg_dir/pubring.kbx ${p:-unknown} (expected 644)"
      _audit_fail=$((_audit_fail + 1))
    fi
  fi
  for f in "$gnupg_dir"/*; do
    [ -e "$f" ] || continue
    [ "$f" = "$gnupg_dir/pubring.kbx" ] && continue
    p=$(_stat_perm "$f")
    _tracked_target=0
    if [ -L "$f" ]; then
      target=$(readlink "$f")
      case "$target" in
        /*) target_path="$target" ;;
        *) target_path="$(dirname "$f")/$target" ;;
      esac
      if [ -e "$target_path" ]; then
        p=$(_stat_perm "$target_path")
      fi
      case "$target_path" in
        "$DOTFILES_ROOT"/*) _tracked_target=1 ;;
      esac
    fi
    if [ -S "$f" ] || [ -d "$f" ]; then
      if [ "$p" = "700" ]; then
        echo "✅ $f 700 (socket/dir)"
      else
        echo "⚠️  $f ${p:-unknown} (expected 700 for socket/dir)"
        _audit_fail=$((_audit_fail + 1))
      fi
    elif [ "$_tracked_target" -eq 1 ]; then
      if [ "$p" = "644" ]; then
        echo "✅ $f 644 (tracked repo file)"
      else
        echo "⚠️  $f ${p:-unknown} (expected 644 for tracked repo file)"
        _audit_fail=$((_audit_fail + 1))
      fi
    else
      if [ "$p" = "600" ]; then
        echo "✅ $f 600"
      else
        echo "⚠️  $f ${p:-unknown} (expected 600 — secret material is world/group readable)"
        _audit_fail=$((_audit_fail + 1))
      fi
    fi
  done
else
  echo "⚠️  $gnupg_dir missing"
  _flag_fail
fi

# Any ⚠️ finding above makes this a failed audit.
if [ "$_audit_fail" -gt 0 ]; then
  echo
  echo "Audit FAILED: $_audit_fail finding(s)."
  exit 1
fi
exit 0

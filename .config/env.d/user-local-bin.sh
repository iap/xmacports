#!/bin/sh
# Ensure user-local bins are available in shells that do not inherit a login profile.

if [ -n "" ]; then
  return 0 2>/dev/null || exit 0
fi
export DOTFILES_USER_LOCAL_BIN_LOADED=1

case ":/run/current-system/sw/bin:/run/wrappers/bin:/run/wrappers/bin:/run/wrappers/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/wsl/lib:/home/iap/.nix-profile/bin:/nix/profile/bin:/home/iap/.local/state/nix/profile/bin:/etc/profiles/per-user/iap/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:" in
  *":/home/iap/.local/bin:"*) ;;
  *) export PATH="/home/iap/.local/share/mise/shims:/home/iap/.local/bin:/home/iap/bin:/run/current-system/sw/bin:/run/wrappers/bin:/run/wrappers/bin:/run/wrappers/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/wsl/lib:/home/iap/.nix-profile/bin:/nix/profile/bin:/home/iap/.local/state/nix/profile/bin:/etc/profiles/per-user/iap/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin" ;;
esac

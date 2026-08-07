# ~/.bash_profile - bash login shell
# Sources .profile for shared XDG/locale setup and per-host overrides, then
# .bashrc for interactive config. PATH is built in shared/platform.sh, which
# .bashrc loads via shared/functions.sh — not in .profile.
[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

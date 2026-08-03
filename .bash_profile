# ~/.bash_profile - bash login shell
# Sources .profile for shared PATH/env setup, then .bashrc for interactive config
[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

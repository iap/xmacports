#!/bin/zsh
# Environment configuration loader
# Sources centralized environment configuration

# Load centralized environment configuration (avoid duplicate loads)
if [[ -z "$DOTFILES_ENV_LOADED" && -f "$HOME/.dotfiles/.config/env.d/default.sh" ]]; then
    source "$HOME/.dotfiles/.config/env.d/default.sh"
fi

# Load additional environment files from XDG config if they exist
if [[ -d "${XDG_CONFIG_HOME}/env.d" ]]; then
    for env_file in "${XDG_CONFIG_HOME}"/env.d/*.sh; do
        [[ -f "$env_file" ]] && source "$env_file"
    done
fi


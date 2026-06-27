#!/bin/zsh
# Environment configuration loader

set -u

# Avoid duplicate loads
if [[ -z "${DOTFILES_ENV_LOADED:-}" && -f "$HOME/.dotfiles/.config/env.d/platform.sh" ]]; then
    source "$HOME/.dotfiles/.config/env.d/platform.sh"
fi

# Load additional environment files from XDG config if they exist
if [[ -d "${XDG_CONFIG_HOME}/env.d" ]]; then
    for env_file in "${XDG_CONFIG_HOME}"/env.d/*.sh; do
        [[ -f "$env_file" ]] || continue
        case "$(basename "$env_file")" in
            platform.sh|foundry.sh) continue ;;
        esac
        source "$env_file"
    done
fi

#!/bin/sh

cp -R .config "$HOME/"

OS="$(uname -s)"

case "$OS" in
    Linux*)
        if [ -f /etc/nixos ]; then
            echo "This is NixOS."
        else
            echo "This is a Linux distribution that is not NixOS."
        fi
        ;;
    Darwin*)
        NU_CONF_DIR="$HOME/Library/Application Support/nushell"
        cp nu_config/*.nu "$NU_CONF_DIR/"
        darwin-rebuild switch --flake "$HOME/.config/nix-darwin"
        cp "$HOME/.config/nix-darwin/flake.lock" .config/nix-darwin/
        git status
        ;;
    *)
        echo "Unsupported operating system: $OS"
        ;;
esac

#!/bin/sh

###### Functions #######


########################



git pull

cp -R .config "$HOME/"

OS="$(uname -s)"

case "$OS" in
    Linux*)
        cp "$HOME/.config/nix-darwin/home-common.nix" "$HOME/.config/home-manager"
        rm -rf "$HOME/.config/nix-darwin"
        if command -v home-manager >/dev/null 2>&1; then
            echo "home-manager is available in the PATH; updating."
            nix-channel --update
        else
            echo "home-manager is not available in the PATH; installing."
            nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
            nix-channel --update
            nix-shell '<home-manager>' -A install
        fi
        home-manager switch
        if [ -f /etc/nixos ]; then
            echo "This is NixOS."
        else
            echo "This is a Linux distribution that is not NixOS."
        fi
        cp "$HOME/.config/home-manager/flake.nix" .config/home-manager/
        ;;
    Darwin*)
        NU_CONF_DIR="$HOME/Library/Application Support/nushell"
        cp nu_config/*.nu "$NU_CONF_DIR/"
        darwin-rebuild switch --flake "$HOME/.config/nix-darwin"
        cp "$HOME/.config/nix-darwin/flake.lock" .config/nix-darwin/
        ;;
    *)
        echo "Unsupported operating system: $OS"
        ;;
esac

shellcheck build.sh
git status

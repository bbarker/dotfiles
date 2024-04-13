#!/bin/sh

###### Functions #######



########################



git pull

cp -R .config "$HOME/"

OS="$(uname -s)"

case "$OS" in
    Linux*)
        NU_CONF_DIR="$HOME/.config/nushell"
        ;;
    Darwin*)
        NU_CONF_DIR="$HOME/Library/Application Support/nushell"
        ;;        
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac
mkdir -p "$NU_CONF_DIR"
cp nu_config/*.nu "$NU_CONF_DIR/"


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
if [ -d /etc/nixos ]; then
    echo "This is NixOS."
else
    echo "This is a Linux distribution that is not NixOS."
fi
cp "$HOME/.config/home-manager/flake.lock" .config/home-manager/

shellcheck build.sh
git status

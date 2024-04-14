#!/bin/sh

###### Functions #######

desiredSystem() {
    OS="$1"
    ARCH="$2"
    case "$OS" in
        Linux)
            case "$ARCH" in
                i686) echo "i686-linux" ;;
                x86_64) echo "x86_64-linux" ;;
                aarch64) echo "aarch64-linux" ;;
                *) echo "Unsupported architecture: $ARCH for Linux" >&2; exit 1 ;;
            esac ;;
        Darwin)
            case "$ARCH" in
                x86_64) echo "x86_64-darwin" ;;
                aarch64) echo "aarch64-darwin" ;;
                *) echo "Unsupported architecture: $ARCH for Darwin" >&2; exit ;;
            esac ;;
    esac
}

########################


git pull

cp -R .config "$HOME/"

OS="$(uname -s)"
ARCH_NAME="$(uname -m)"
HOSTNAME="$(hostname)"
DESIRED_SYSTEM=$(desiredSystem "${OS}" "${ARCH_NAME}")
if sed -i "s/SYSTEM_PLACEHOLDER/${DESIRED_SYSTEM}/g" "$HOME/.config/home-manager/flake.nix"; then
    echo "Substitution complete. The Nix system is now set to ${DESIRED_SYSTEM}."
else
    echo "Error determining the desired Nix system."
fi

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
cp "$HOME/.config/home-manager/flake.lock" ".config/home-manager/flake-$ARCH_NAME-$OS-$HOSTNAME.lock"

shellcheck build.sh
git status

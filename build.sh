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


REPO_DIR=$(pwd)
git pull

cp -R .config "$HOME/"

NIX_CONF_FILE="$HOME/.config/nix/nix.conf"
# For new nix installations
if [ -f "$NIX_CONF_FILE" ]; then
    echo "Found nix.conf"
else
    echo "nix.conf not found; creating default."
    cat "experimental-features = nix-command flakes configurable-impure-env" > "$NIX_CONF_FILE"
fi

OS="$(uname -s)"
ARCH_NAME="$(uname -m)"
if [ "$ARCH_NAME" = "arm64" ] && [ "$OS" = "Darwin" ]; then
    ARCH_NAME="aarch64"
fi
HOSTNAME="$(hostname)"
HOME_NIX_FILE="home-$ARCH_NAME-$OS-$HOSTNAME.nix"
HOME_NIX_FILE_PATH="$HOME/.config/home-manager/$HOME_NIX_FILE"
echo "Looking for $HOME_NIX_FILE_PATH"
if [ -f "$HOME_NIX_FILE_PATH" ]; then
    echo "Found $HOME_NIX_FILE"
    mv "$HOME_NIX_FILE_PATH" "$HOME/.config/home-manager/home.nix"
else
    echo "Custom config not found; using default home.nix."
fi
# case "$HOSTNAME" in
#     C02FD66VMD6M) mv "$HOME/.config/home-manager/home-czrmac.nix" "$HOME/.config/home-manager/home.nix" ;;
#     *) echo "Using default home manager config.";;
# esac
DESIRED_SYSTEM=$(desiredSystem "${OS}" "${ARCH_NAME}")
if sed -i='' "s/SYSTEM_PLACEHOLDER/${DESIRED_SYSTEM}/g" "${HOME}/.config/home-manager/flake.nix" "${HOME}/.config/home-manager/home-common.nix"; then
    echo "Substitution complete. The Nix system is now set to ${DESIRED_SYSTEM}."
else
    echo "Error determining the desired Nix system."
fi

DESIRED_VERSION="24.11"
if sed -i='' "s/NIX_VERSION_PLACEHOLDER/${DESIRED_VERSION}/g" "${HOME}/.config/home-manager/flake.nix"; then
    echo "Substitution complete. The Nix version is now set to ${DESIRED_VERSION}."
else
    echo "Error substituting the desired Nix version."
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

cd "$HOME/.config/home-manager/" || { echo "couldn't cd to home-manager config dir"; exit;}
nix flake update
cd "$REPO_DIR" || { echo "couldn't cd to REPO_DIR"; exit; }
home-manager switch

cp "$HOME/.config/home-manager/flake.lock" "flake_locks/flake-$ARCH_NAME-$OS-$HOSTNAME.lock"

shellcheck build.sh
git status

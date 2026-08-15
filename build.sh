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
                *) echo "Unsupported architecture: $ARCH for Darwin" >&2; exit 1 ;;
            esac ;;
        *)
            echo "Unsupported OS: $OS" >&2; exit 1 ;;
    esac
}

sed_i() {
    pattern="$1"
    shift
    for target in "$@"; do
        if [ -f "$target" ]; then
            if [ "$OS" = "Darwin" ]; then
                sed -i '' "$pattern" "$target"
            else
                sed -i "$pattern" "$target"
            fi
        fi
    done
}

########################

REPO_DIR=$(pwd)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git pull || echo "Warning: git pull failed, continuing..."
fi

OS="$(uname -s)"
ARCH_NAME="$(uname -m)"
if [ "$ARCH_NAME" = "arm64" ] && [ "$OS" = "Darwin" ]; then
    ARCH_NAME="aarch64"
fi
HOSTNAME="$(hostname)"
CURRENT_USER="${USER:-$(id -un)}"
CURRENT_HOME="${HOME:-/home/$CURRENT_USER}"

# Copy configuration files into user's home directory
cp -R .config "$HOME/"

# Ensure nix.conf exists and has experimental features enabled
NIX_CONF_DIR="$HOME/.config/nix"
NIX_CONF_FILE="$NIX_CONF_DIR/nix.conf"
mkdir -p "$NIX_CONF_DIR"
if [ -f "$NIX_CONF_FILE" ]; then
    echo "Found nix.conf"
    if ! grep -q "experimental-features" "$NIX_CONF_FILE"; then
        echo "experimental-features = nix-command flakes configurable-impure-env" >> "$NIX_CONF_FILE"
    fi
else
    echo "nix.conf not found; creating default."
    echo "experimental-features = nix-command flakes configurable-impure-env" > "$NIX_CONF_FILE"
fi

HOME_NIX_FILE="home-$ARCH_NAME-$OS-$HOSTNAME.nix"
HOME_NIX_FILE_PATH="$HOME/.config/home-manager/$HOME_NIX_FILE"
echo "Looking for $HOME_NIX_FILE_PATH"
if [ -f "$HOME_NIX_FILE_PATH" ]; then
    echo "Found $HOME_NIX_FILE"
    mv "$HOME_NIX_FILE_PATH" "$HOME/.config/home-manager/home.nix"
else
    echo "Custom config not found; using default home.nix."
fi

DESIRED_SYSTEM=$(desiredSystem "${OS}" "${ARCH_NAME}")
sed_i "s/SYSTEM_PLACEHOLDER/${DESIRED_SYSTEM}/g" "${HOME}/.config/home-manager/flake.nix" "${HOME}/.config/home-manager/home-common.nix"
echo "Substitution complete. The Nix system is now set to ${DESIRED_SYSTEM}."

DESIRED_VERSION="25.05"
sed_i "s/NIX_VERSION_PLACEHOLDER/${DESIRED_VERSION}/g" "${HOME}/.config/home-manager/flake.nix"
echo "Substitution complete. The Nix version is now set to ${DESIRED_VERSION}."

# Adapt username and home directory for current user
sed_i "s/USER_PLACEHOLDER/${CURRENT_USER}/g; s/\"bbarker\"/\"${CURRENT_USER}\"/g" "${HOME}/.config/home-manager/flake.nix" "${HOME}/.config/home-manager/home.nix"
sed_i "s|HOME_DIR_PLACEHOLDER|${CURRENT_HOME}|g; s|/home/bbarker|${CURRENT_HOME}|g; s|/Users/bbarker|${CURRENT_HOME}|g" "${HOME}/.config/home-manager/home.nix"

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
if [ -d "nu_config" ]; then
    cp nu_config/*.nu "$NU_CONF_DIR/"
fi

# Update flake inputs
cd "$HOME/.config/home-manager/" || { echo "couldn't cd to home-manager config dir"; exit 1; }
nix --extra-experimental-features "nix-command flakes" flake update
cd "$REPO_DIR" || { echo "couldn't cd to REPO_DIR"; exit 1; }

if command -v home-manager >/dev/null 2>&1; then
    echo "home-manager is available in the PATH; switching."
    # --impure required for nixGL (GPU support on non-NixOS)
    home-manager --extra-experimental-features "nix-command flakes" switch --flake "$HOME/.config/home-manager#${CURRENT_USER}" -b backup --impure
else
    echo "home-manager is not available in the PATH; bootstrapping via flake."
    # --impure required for nixGL (GPU support on non-NixOS)
    nix --extra-experimental-features "nix-command flakes" run "github:nix-community/home-manager/release-${DESIRED_VERSION}" -- switch --flake "$HOME/.config/home-manager#${CURRENT_USER}" -b backup --impure
fi

mkdir -p "$REPO_DIR/flake_locks"
if [ -f "$HOME/.config/home-manager/flake.lock" ]; then
    cp "$HOME/.config/home-manager/flake.lock" "$REPO_DIR/flake_locks/flake-$ARCH_NAME-$OS-$HOSTNAME.lock"
fi

# Ensure Nix/Home-Manager profile binaries are in PATH for subsequent steps
for p in "$HOME/.nix-profile/bin" "/etc/profiles/per-user/$CURRENT_USER/bin" "/nix/var/nix/profiles/default/bin" "$HOME/.local/state/nix/profiles/profile/bin" "$HOME/.local/state/nix/profiles/home-manager/bin"; do
    if [ -d "$p" ]; then
        case ":$PATH:" in
            *":$p:"*) ;;
            *) PATH="$p:$PATH" ;;
        esac
    fi
done
export PATH
# shellcheck disable=SC1091
if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
elif [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix.sh" ]; then
    . "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
fi
# shellcheck disable=SC1091
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

# Optional: Install helix grammars (non-blocking, headless)
export GIT_TERMINAL_PROMPT=0
if command -v hx >/dev/null 2>&1; then
    echo "Fetching and building Helix grammars (optional)..."
    hx --grammar fetch 2>/dev/null || true
    if command -v clang >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
        hx --grammar build 2>/dev/null || true
    elif command -v nix-shell >/dev/null 2>&1; then
        nix-shell -p clang --run "hx --grammar build" 2>/dev/null || true
    fi
elif command -v nix-shell >/dev/null 2>&1; then
    echo "Attempting Helix grammar fetch via nix-shell (optional)..."
    nix-shell -p helix clang --run "hx --grammar fetch && hx --grammar build" 2>/dev/null || true
fi

COB_QUERY_SRC="$HOME/.config/helix/runtime/grammars/sources/cobweb/queries"
COB_QUERY_DIR="$HOME/.config/helix/runtime/queries/cobweb"
if [ -d "$COB_QUERY_SRC" ]; then
    mkdir -p "$COB_QUERY_DIR"
    cp -r "$COB_QUERY_SRC/." "$COB_QUERY_DIR/" 2>/dev/null || true
fi

# Deploy Zed config: merge base settings with machine-local overrides
ZED_DEST="$HOME/.config/zed"
mkdir -p "$ZED_DEST"
if [ -d ".config/zed" ]; then
    cp -R .config/zed/. "$ZED_DEST/"
fi
ZED_BASE="$ZED_DEST/settings.json"
ZED_LOCAL="$ZED_DEST/settings.local.json"
if [ -f "$ZED_LOCAL" ] && [ -f "$ZED_BASE" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -s '.[0] * .[1]' "$ZED_BASE" "$ZED_LOCAL" > "$ZED_DEST/settings.json.tmp" && mv "$ZED_DEST/settings.json.tmp" "$ZED_BASE"
    elif command -v nix-shell >/dev/null 2>&1; then
        nix-shell -p jq --run "jq -s '.[0] * .[1]' '$ZED_BASE' '$ZED_LOCAL' > '$ZED_DEST/settings.json.tmp'" && mv "$ZED_DEST/settings.json.tmp" "$ZED_BASE"
    fi
fi

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck build.sh
elif command -v nix-shell >/dev/null 2>&1; then
    nix-shell -p shellcheck --run "shellcheck build.sh"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git status
fi

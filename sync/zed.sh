#!/bin/sh
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZED_SRC="$HOME/.config/zed"
ZED_DEST="$DOTFILES_DIR/.config/zed"

cp -R "$ZED_SRC/" "$ZED_DEST/"

# Strip machine-specific agent_servers, save as settings.base.json, remove raw copy
jq 'del(.agent_servers)' "$ZED_DEST/settings.json" > "$ZED_DEST/settings.base.json"
rm "$ZED_DEST/settings.json"

# Remove sensitive files
rm -f "$ZED_DEST/development_credentials"

echo "Zed config synced to $ZED_DEST"

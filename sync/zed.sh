#!/bin/sh
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZED_SRC="$HOME/.config/zed"
ZED_DEST="$DOTFILES_DIR/.config/zed"

mkdir -p "$ZED_DEST"

# Copy all zed config except sensitive/machine-specific files
rsync -a --exclude='settings.local.json' --exclude='development_credentials' "$ZED_SRC/" "$ZED_DEST/"

# Strip agent_servers (and any other machine-specific keys) from settings.json
jq 'del(.agent_servers)' "$ZED_DEST/settings.json" > "$ZED_DEST/settings.json.tmp"
mv "$ZED_DEST/settings.json.tmp" "$ZED_DEST/settings.json"

echo "Zed config synced to $ZED_DEST"

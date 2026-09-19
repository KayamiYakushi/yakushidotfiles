#!/usr/bin/env bash
set -u

BASE="$HOME/.config/quickshell/hyprquickpaper"
INDEXER="$BASE/index.py"

count=$(python3 "$INDEXER" 2>/dev/null || echo 0)

if [[ "$count" == "0" ]]; then
    notify-send "Yakushi Wallpaper" "No images found under ~/Documents" 2>/dev/null || true
    exit 0
fi

exec qs -p "$BASE/shell.qml"

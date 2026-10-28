#!/bin/sh
# SUPER + W: index the images under ~/Documents, then open the picker.

dir="$HOME/.config/quickshell/wallpicker"
found="$(python3 "$dir/index.py" 2>/dev/null)"

if [ "${found:-0}" = 0 ]; then
    notify-send "Wallpaper" "No images found under ~/Documents" 2>/dev/null
    exit 0
fi

exec qs -p "$dir/shell.qml"

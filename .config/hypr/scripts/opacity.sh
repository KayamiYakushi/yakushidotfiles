#!/bin/sh
# SUPER + O: pick how opaque windows are (100 % ... 40 %).
# Writes active_opacity and inactive_opacity in hyprland.lua (fullscreen
# windows keep fullscreen_opacity = 1.0) and reloads Hyprland.

conf="$HOME/.config/hypr/hyprland.lua"

pick="$(for pct in 100 90 80 70 60 50 40; do echo "$pct%"; done |
    rofi -dmenu -p "" -no-custom)" || exit 0

pct="${pick%\%}"
case "$pct" in
    ''|*[!0-9]*) exit 0 ;;
esac

value="$(awk -v p="$pct" 'BEGIN { printf "%.1f", p / 100 }')"
sed -i -E "s/\b(active_opacity|inactive_opacity)( *= *)[0-9.]+/\1\2$value/" "$conf"
hyprctl reload >/dev/null

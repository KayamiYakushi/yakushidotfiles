#!/bin/sh
# SUPER + CTRL + Escape: for when the top bar, Settings or a pop-up stops
# answering. Ends every Quickshell of yours at once (and Waybar and rofi, if
# they are stuck too), then starts the top bar again. Your windows and apps
# are not touched. A single Hyprland shortcut runs it, so it works even
# while Quickshell itself is frozen.
uid="$(id -u)"
for name in qs quickshell waybar rofi; do
    pkill -KILL -u "$uid" -x "$name" 2>/dev/null
done
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$uid}/yakushi"
rm -f "$runtime_root/topbar.pid" "$runtime_root/settings.pid"
sleep 0.3
exec sh "$HOME/.config/quickshell/scripts/yakushi-bar.sh" start

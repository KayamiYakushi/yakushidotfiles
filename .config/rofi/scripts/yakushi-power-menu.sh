#!/bin/sh

choice="$(
    printf '%s\n' \
        "Lock" \
        "Suspend" \
        "Logout" \
        "Reboot" \
        "Shutdown" |
        rofi -dmenu -i -p "Power"
)"

case "$choice" in
    "Lock")
        setsid hyprlock >/dev/null 2>&1 &
        ;;
    "Suspend")
        systemctl suspend
        ;;
    "Logout")
        hyprctl dispatch exit
        ;;
    "Reboot")
        systemctl reboot
        ;;
    "Shutdown")
        systemctl poweroff
        ;;
esac

#!/bin/sh
# Power menu (SUPER + ` and the bar's power button).
#
# With the island bar running, this opens the island's own menu. Otherwise
# (Waybar style) it shows a rofi menu styled to match. Destructive actions
# ask once more before running. Calling it again closes an open menu.

qml="$HOME/.config/quickshell/topbar-shell.qml"
pid_file="${XDG_RUNTIME_DIR:-/tmp/yakushi-$(id -u)}/yakushi/topbar.pid"

if [ -r "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
    qs -p "$qml" ipc call topbar power >/dev/null 2>&1 && exit 0
fi

if pgrep -x rofi >/dev/null 2>&1; then
    pkill -x rofi
    exit 0
fi

theme="$HOME/.config/rofi/power.rasi"

# Follow the accent chosen in Settings -> Appearance.
accent="$(grep -o '"accent"[[:space:]]*:[[:space:]]*"#[0-9a-fA-F]\{6\}"' \
    "$HOME/.config/quickshell/yakushi-ui.local.json" 2>/dev/null | grep -o '#[0-9a-fA-F]\{6\}')"
accent="${accent:-#ffffff}"

uptime_text="$(uptime -p 2>/dev/null | sed 's/^up /up /')"

tile() {
    # Big glyph, label below; entries are separated by '|'
    printf "<span font='JetBrainsMono Nerd Font 20'>%s</span>\n%s|" "$1" "$2"
}

menu() {
    rofi -dmenu -i -sep '|' -eh 2 -markup-rows -no-custom \
        -theme "$theme" -theme-str "* { accent: $accent; }" \
        -mesg "$1" -format i
}

confirm() {
    choice="$(
        { tile "󰜺" "Cancel"; tile "$1" "$2"; } |
            rofi -dmenu -i -sep '|' -eh 2 -markup-rows -no-custom \
                -theme "$theme" \
                -theme-str "* { accent: #ff003c; } window { width: 260px; } listview { columns: 2; }" \
                -mesg "$2?" -format i -selected-row 0
    )"
    [ "$choice" = 1 ]
}

choice="$(
    {
        tile "󰌾" "Lock"
        tile "󰒲" "Suspend"
        tile "󰍃" "Log out"
        tile "󰜉" "Restart"
        tile "󰐥" "Shut down"
    } | menu "POWER   ·   ${uptime_text:-}"
)"

case "$choice" in
    0)
        pidof hyprlock >/dev/null || setsid hyprlock >/dev/null 2>&1 &
        ;;
    1)
        systemctl suspend
        ;;
    2)
        confirm "󰍃" "Log out" || exit 0
        out="$(hyprctl eval 'hl.dispatch(hl.dsp.exit())' 2>&1)"
        case "$out" in *rror*|*nknown*|*nvalid*) hyprctl dispatch exit ;; esac
        ;;
    3)
        confirm "󰜉" "Restart" && systemctl reboot
        ;;
    4)
        confirm "󰐥" "Shut down" && systemctl poweroff
        ;;
esac

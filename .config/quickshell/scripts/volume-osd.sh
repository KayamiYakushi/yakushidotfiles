#!/bin/sh

qml="$HOME/.config/quickshell/volume-osd-shell.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$UID}/yakushi"
pid_file="$runtime_root/volume-osd.pid"
log_file="/tmp/yakushi-volume-osd.log"

mkdir -p "$runtime_root"

case "${1:-}" in
    up)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
        ;;
    down)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
    show)
        ;;
    *)
        printf 'Usage: %s up|down|mute|show\n' "$0" >&2
        exit 2
        ;;
esac

if [ -r "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        qs -p "$qml" ipc call volumeOsd show >/dev/null 2>&1 || true
        exit 0
    fi

    rm -f "$pid_file"
fi

qs -n -p "$qml" >"$log_file" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$pid_file"

#!/bin/sh
# volume-osd.sh up|down|mute|show
# Changes the volume with wpctl, then shows the volume pill. A running pill
# is reused over IPC; otherwise a fresh one is started (it quits by itself).

case "$1" in
    up)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    show) ;;
    *)    echo "usage: volume-osd.sh up|down|mute|show" >&2; exit 2 ;;
esac

shell_file="$HOME/.config/quickshell/volume-osd-shell.qml"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/yakushi"
pid_file="$state_dir/volume-osd.pid"
mkdir -p "$state_dir"

running_pid=$(cat "$pid_file" 2>/dev/null)
if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    qs -p "$shell_file" ipc call volumeOsd show >/dev/null 2>&1 && exit 0
fi

qs -n -p "$shell_file" >/dev/null 2>&1 &
echo $! > "$pid_file"

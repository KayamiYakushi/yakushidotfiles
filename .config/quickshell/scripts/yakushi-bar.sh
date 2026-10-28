#!/bin/sh
# Start / stop the Yakushi top bar.
#
#   yakushi-bar.sh start     Start the bar chosen in Settings -> Top Bar
#                            (and stop the other one).
#   yakushi-bar.sh stop      Stop whichever bar is running.
#   yakushi-bar.sh toggle    Stop if running, start otherwise.
#   yakushi-bar.sh restart   Stop, then start.
#
# The style lives in ~/.config/quickshell/yakushi-topbar.local.json
# ("island" by default, "waybar" for the classic bar).

state="$HOME/.config/quickshell/yakushi-topbar.local.json"
island_qml="$HOME/.config/quickshell/topbar-shell.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$(id -u)}/yakushi"
pid_file="$runtime_root/topbar.pid"
log_file="/tmp/yakushi-topbar.log"

mkdir -p "$runtime_root"

style() {
    if [ -r "$state" ] && grep -q '"style"[[:space:]]*:[[:space:]]*"waybar"' "$state"; then
        echo waybar
    else
        echo island
    fi
}

island_pid() {
    [ -r "$pid_file" ] || return 1
    pid="$(cat "$pid_file" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && echo "$pid"
}

island_running() {
    island_pid >/dev/null
}

waybar_running() {
    pgrep -x waybar >/dev/null 2>&1
}

stop_island() {
    pid="$(island_pid)" && kill "$pid" 2>/dev/null
    rm -f "$pid_file"
}

stop_waybar() {
    pkill -x waybar 2>/dev/null
}

start_island() {
    island_running && return 0
    setsid qs -n -p "$island_qml" >"$log_file" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$pid_file"
}

start_waybar() {
    waybar_running && return 0
    setsid waybar >/tmp/yakushi-waybar.log 2>&1 </dev/null &
}

start() {
    # First run: write the defaults so the bar has a file to watch.
    [ -e "$state" ] ||
        python3 "$HOME/.config/quickshell/scripts/yakushi-topbarctl.py" init >/dev/null 2>&1

    if [ "$(style)" = waybar ]; then
        stop_island
        start_waybar
    else
        stop_waybar
        start_island
    fi
}

stop() {
    stop_island
    stop_waybar
}

case "${1:-start}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    toggle)
        if island_running || waybar_running; then
            stop
        else
            start
        fi
        ;;
    restart)
        stop
        sleep 0.2
        start
        ;;
    *)
        printf 'Usage: %s start|stop|toggle|restart\n' "$0" >&2
        exit 2
        ;;
esac

#!/bin/sh
# Set the wallpaper with awww (starting its daemon when needed).
# usage: apply.sh <image>

img="$1"
[ -f "$img" ] || { echo "apply.sh: no such image: $img" >&2; exit 1; }

awww query >/dev/null 2>&1 || {
    awww-daemon >/tmp/yakushi-awww-daemon.log 2>&1 &
    sleep 0.5
}

exec awww img "$img" --transition-type random --transition-duration 1

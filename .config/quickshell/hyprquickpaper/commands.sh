#!/usr/bin/env bash
set -u

image="${1:-}"

if [[ -z "$image" || ! -f "$image" ]]; then
    echo "Invalid wallpaper: $image" >&2
    exit 1
fi

if ! awww query >/dev/null 2>&1; then
    awww-daemon >/tmp/yakushi-awww-daemon.log 2>&1 &
    sleep 0.5
fi

exec awww img "$image" --transition-type random --transition-duration 1

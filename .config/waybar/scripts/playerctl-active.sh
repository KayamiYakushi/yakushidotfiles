#!/usr/bin/env bash

if command -v playerctld >/dev/null 2>&1; then
    if ! pgrep -x playerctld >/dev/null 2>&1; then
        playerctld daemon >/tmp/yakushi-playerctld.log 2>&1 &
        sleep 0.2
    fi

    if playerctl --player=playerctld status >/dev/null 2>&1; then
        echo "playerctld"
        exit 0
    fi
fi

while read -r player; do
    if [[ "$(playerctl --player="$player" status 2>/dev/null)" == "Playing" ]]; then
        echo "$player"
        exit 0
    fi
done < <(playerctl -l 2>/dev/null)

exit 1

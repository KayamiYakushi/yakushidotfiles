#!/usr/bin/env bash

DISPLAY_CHARS=24
SLEEP=0.5

last_text=""
last_player=""

fit_text() {
    local text="$1"

    if [[ ${#text} -gt $DISPLAY_CHARS ]]; then
        text="${text:0:$((DISPLAY_CHARS - 1))}…"
    fi

    printf "%-${DISPLAY_CHARS}s" "$text"
}

while true; do
    PLAYER=""

    while read -r p; do
        if [[ "$(playerctl --player="$p" status 2>/dev/null)" == "Playing" ]]; then
            PLAYER="$p"
            break
        fi
    done < <(playerctl -l 2>/dev/null)

    if [[ -n "$PLAYER" ]]; then
        title="$(playerctl --player="$PLAYER" metadata --format '{{ title }}' 2>/dev/null)"
        artist="$(playerctl --player="$PLAYER" metadata --format '{{ artist }}' 2>/dev/null)"

        if [[ -n "$artist" ]]; then
            text="$title - $artist"
        else
            text="$title"
        fi

        last_text="$text"
        last_player="$PLAYER"

        display="$(fit_text "$text")"

        jq -cn             --arg text "♪  $display"             --arg class "playing"             --arg tooltip "$text"             '{text:$text, class:$class, tooltip:$tooltip}'

    else
        if [[ -n "$last_player" ]]; then
            STATUS="$(playerctl --player="$last_player" status 2>/dev/null)"
            display="$(fit_text "$last_text")"

            if [[ "$STATUS" == "Paused" ]]; then
                jq -cn                     --arg text "♪  $display"                     --arg class "paused"                     --arg tooltip "$last_text"                     '{text:$text, class:$class, tooltip:$tooltip}'
            else
                jq -cn                     --arg text "♪  $display"                     --arg class "stopped"                     --arg tooltip "$last_text"                     '{text:$text, class:$class, tooltip:$tooltip}'
            fi
        else
            jq -cn '{text:"", class:"empty", tooltip:""}'
        fi
    fi

    sleep "$SLEEP"
done

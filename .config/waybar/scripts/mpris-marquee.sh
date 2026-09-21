#!/usr/bin/env bash

MAX_CHARS=30
SLEEP=0.4
CAPSULE_CTL="$HOME/.config/waybar/scripts/yakushi-mpris-capsulectl.py"
last_capsule_state=""

set_capsule() {
    local wanted="$1"
    if [[ "$last_capsule_state" == "$wanted" ]]; then
        return
    fi
    last_capsule_state="$wanted"
    "$CAPSULE_CTL" "$wanted" >/dev/null 2>&1 || true
}

ensure_playerctld() {
    if command -v playerctld >/dev/null 2>&1; then
        if ! pgrep -x playerctld >/dev/null 2>&1; then
            playerctld daemon >/tmp/yakushi-playerctld.log 2>&1 &
            sleep 0.2
        fi
        return 0
    fi
    return 1
}

pick_player() {
    if ensure_playerctld; then
        if playerctl --player=playerctld status >/dev/null 2>&1; then
            printf '%s\n' "playerctld"
            return 0
        fi
    fi

    local p
    while read -r p; do
        if [[ "$(playerctl --player="$p" status 2>/dev/null)" == "Playing" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done < <(playerctl -l 2>/dev/null)

    return 1
}

fit_text() {
    local text="$1"
    if [[ ${#text} -gt $MAX_CHARS ]]; then
        text="${text:0:$((MAX_CHARS - 1))}…"
    fi
    printf '%s' "$text"
}

last_full=""

while true; do
    PLAYER="$(pick_player 2>/dev/null || true)"

    if [[ -n "$PLAYER" ]]; then
        STATUS="$(playerctl --player="$PLAYER" status 2>/dev/null || true)"
        title="$(playerctl --player="$PLAYER" metadata --format '{{ title }}' 2>/dev/null || true)"
        artist="$(playerctl --player="$PLAYER" metadata --format '{{ artist }}' 2>/dev/null || true)"

        if [[ -n "$title" ]]; then
            if [[ -n "$artist" ]]; then
                full="$title - $artist"
            else
                full="$title"
            fi

            last_full="$full"
            display="$(fit_text "$full")"

            case "$STATUS" in
                Playing) class="playing" ;;
                Paused) class="paused" ;;
                *) class="stopped" ;;
            esac

            set_capsule show
            jq -cn --arg text "♪  $display" --arg class "$class" --arg tooltip "$full"                 '{text:$text, class:$class, tooltip:$tooltip}'
        elif [[ -n "$last_full" ]]; then
            display="$(fit_text "$last_full")"
            set_capsule show
            jq -cn --arg text "♪  $display" --arg class "paused" --arg tooltip "$last_full"                 '{text:$text, class:$class, tooltip:$tooltip}'
        else
            set_capsule hide
            jq -cn '{text:"", class:"empty", tooltip:""}'
        fi
    elif [[ -n "$last_full" ]]; then
        display="$(fit_text "$last_full")"
        set_capsule show
        jq -cn --arg text "♪  $display" --arg class "stopped" --arg tooltip "$last_full"             '{text:$text, class:$class, tooltip:$tooltip}'
    else
        set_capsule hide
        jq -cn '{text:"", class:"empty", tooltip:""}'
    fi

    sleep "$SLEEP"
done

#!/usr/bin/env bash
# Song line and media buttons for the hyprlock screen.
#
#   now-playing.sh           "title  ·  artist", scrolling when it is long
#   now-playing.sh previous  previous-track glyph
#   now-playing.sh pause     play or pause glyph, whichever fits
#   now-playing.sh next      next-track glyph
#
# Prints nothing when no player is playing or paused. Goes through
# playerctld, so a paused player keeps its buttons.

WINDOW=36      # characters visible at once
LIMIT=60       # longer lines are cut with an ellipsis first

pc() { playerctl --player=playerctld "$@" 2>/dev/null; }

state=$(pc status)
[[ $state == Playing || $state == Paused ]] || exit 0

case $1 in
    previous) printf '󰒮\n'; exit ;;
    next)     printf '󰒭\n'; exit ;;
    pause)    [[ $state == Playing ]] && printf '󰏤\n' || printf '󰐊\n'; exit ;;
esac

song=$(pc metadata --format '{{ title }}')
who=$(pc metadata --format '{{ artist }}')
line=${song}${who:+  ·  $who}
[[ -n $line ]] || exit 0

# hyprlock reads Pango markup: escape only what we print
markup() {
    local s=${1//'&'/'&amp;'}
    s=${s//'<'/'&lt;'}
    printf '%s' "${s//'>'/'&gt;'}"
}

(( ${#line} > LIMIT )) && line="${line:0:LIMIT-1}…"

if (( ${#line} > WINDOW )); then
    # one step per second, wrapping round with a gap
    loop="$line     "
    start=$(( $(date +%s) % ${#loop} ))
    doubled="$loop$loop"
    line=${doubled:start:WINDOW}
fi

printf '󰎇  %s\n' "$(markup "$line")"

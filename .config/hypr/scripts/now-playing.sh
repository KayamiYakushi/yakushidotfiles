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
#
# The lock screen asks for these four lines every second or two, for as long
# as it stays locked (all night, maybe). So the player is asked only once a
# second, by whichever line comes first, and the others read that answer
# from a tiny file in your runtime folder; no `date` processes either.

# count characters, not bytes, even without a UTF-8 locale
[[ ${LC_ALL:-${LC_CTYPE:-$LANG}} == *[Uu][Tt][Ff]* ]] || LC_ALL=C.UTF-8

WINDOW=36      # characters visible at once
LIMIT=60       # longer lines are cut with an ellipsis first

dir="${XDG_RUNTIME_DIR:-/tmp/yakushi-$UID}/yakushi"
cache="$dir/now-playing"
now=$EPOCHSECONDS

# the cache: time, status, title, artist (one per line)
info=()
[[ -r $cache ]] && mapfile -t -n 4 info < "$cache"
if (( ${#info[@]} < 2 || now - ${info[0]:-0} >= 1 )); then
    [[ -d $dir ]] || mkdir -p "$dir"
    mapfile -t -n 3 got < <(playerctl --player=playerctld metadata \
        --format $'{{status}}\n{{title}}\n{{artist}}' 2>/dev/null)
    info=("$now" "${got[0]}" "${got[1]}" "${got[2]}")
    printf '%s\n' "${info[@]}" > "$cache"
fi

state=${info[1]}
[[ $state == Playing || $state == Paused ]] || exit 0

case $1 in
    previous) printf '󰒮\n'; exit ;;
    next)     printf '󰒭\n'; exit ;;
    pause)    [[ $state == Playing ]] && printf '󰏤\n' || printf '󰐊\n'; exit ;;
esac

song=${info[2]}
who=${info[3]}
line=${song}${who:+  ·  $who}
[[ -n $line ]] || exit 0

(( ${#line} > LIMIT )) && line="${line:0:LIMIT-1}…"

if (( ${#line} > WINDOW )); then
    # one step per second, wrapping round with a gap
    loop="$line     "
    start=$(( now % ${#loop} ))
    doubled="$loop$loop"
    line=${doubled:start:WINDOW}
fi

# hyprlock reads Pango markup: escape what we print
line=${line//'&'/'&amp;'}
line=${line//'<'/'&lt;'}
line=${line//'>'/'&gt;'}
printf '󰎇  %s\n' "$line"

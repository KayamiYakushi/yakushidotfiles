#!/bin/sh
# Make 500 px tall thumbnails for the wallpaper picker, a few at a time.
# Only images without a thumbnail are processed, so later runs are quick.
# usage: thumbs.sh <picker dir>

conf="$1/settings.json"
images="$(jq -r '.images_dir' "$conf" | sed "s|^~|$HOME|")"
thumbs="$(jq -r '.thumbs_dir' "$conf" | sed "s|^~|$HOME|")"
jobs="$(jq -r '.thumb_jobs // 4' "$conf")"
# never more at once than half the CPU cores (each one can take a few hundred
# MB while it decodes a big photo), and gently: the desktop stays smooth
cores="$(nproc 2>/dev/null || echo 2)"
max=$(( cores / 2 > 1 ? cores / 2 : 1 ))
case "$jobs" in ''|*[!0-9]*) jobs=4 ;; esac
[ "$jobs" -gt "$max" ] && jobs="$max"
[ "$jobs" -lt 1 ] && jobs=1

if command -v magick >/dev/null 2>&1; then
    convert="magick"
elif command -v convert >/dev/null 2>&1; then
    convert="convert"
else
    echo "thumbs.sh: ImageMagick is not installed" >&2
    exit 1
fi

mkdir -p "$thumbs"

# -L: the index holds symlinks to the real images
find -L "$images" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) |
    while IFS= read -r src; do
        out="$thumbs/$(basename "$src")"
        [ -e "$out" ] && continue
        printf '%s\0%s\0' "$src" "$out"
    done |
    nice -n 10 xargs -0 -r -n 2 -P "$jobs" sh -c \
        '"$0" -define jpeg:size=2000x1000 "$1" -thumbnail x500 -strip -quality 85 "$2"' "$convert"

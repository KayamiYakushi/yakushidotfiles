#!/usr/bin/env bash
set -u

CONFIG="$1/config.json"

wallpaper_path=$(jq -r '.wallpaper_path' "$CONFIG")
cache_path=$(jq -r '.cache_path' "$CONFIG")
cache_batch_size=$(jq -r '.cache_batch_size // 20' "$CONFIG")

wallpaper_path="${wallpaper_path/#\~/$HOME}"
cache_path="${cache_path/#\~/$HOME}"

mkdir -p "$cache_path"

if command -v magick >/dev/null 2>&1; then
    image_cmd=(magick)
elif command -v convert >/dev/null 2>&1; then
    image_cmd=(convert)
else
    echo "ImageMagick not found; thumbnails cannot be generated." >&2
    exit 1
fi

find -L "$wallpaper_path" -maxdepth 1 -type f \( \
    -iname "*.jpg" -o \
    -iname "*.jpeg" -o \
    -iname "*.png" -o \
    -iname "*.webp" \
\) -print0 | while IFS= read -r -d '' img; do
    filename=$(basename "$img")
    out="$cache_path/$filename"

    if [[ -f "$out" ]]; then
        continue
    fi

    "${image_cmd[@]}" "$img" -thumbnail x500 -strip -quality 85 "$out" &

    if (( cache_batch_size > 0 )); then
        while (( $(jobs -rp | wc -l) >= cache_batch_size )); do
            wait -n
        done
    fi
done

wait

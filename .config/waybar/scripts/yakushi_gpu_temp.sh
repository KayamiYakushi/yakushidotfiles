#!/bin/sh
for d in /sys/class/hwmon/hwmon*; do
    [ -r "$d/name" ] || continue
    name=$(cat "$d/name" 2>/dev/null)

    case "$name" in
        amdgpu)
            if [ -r "$d/temp1_input" ]; then
                v=$(cat "$d/temp1_input" 2>/dev/null)
                c=$((v / 1000))
                printf 'GPU %s°C\n' "$c"
                exit 0
            fi

            for f in "$d"/temp*_input; do
                [ -r "$f" ] || continue
                v=$(cat "$f" 2>/dev/null)
                [ -n "$v" ] || continue
                c=$((v / 1000))
                printf 'GPU %s°C\n' "$c"
                exit 0
            done
            ;;
    esac
done

printf 'GPU --°C\n'

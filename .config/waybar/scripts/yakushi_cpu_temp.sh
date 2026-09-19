#!/bin/sh
for d in /sys/class/hwmon/hwmon*; do
    [ -r "$d/name" ] || continue
    name=$(cat "$d/name" 2>/dev/null)

    case "$name" in
        k10temp|zenpower|coretemp|cpu_thermal)
            best=""
            for f in "$d"/temp*_input; do
                [ -r "$f" ] || continue
                v=$(cat "$f" 2>/dev/null)
                [ -n "$v" ] || continue

                c=$((v / 1000))

                if [ -z "$best" ] || [ "$c" -gt "$best" ]; then
                    best="$c"
                fi
            done

            if [ -n "$best" ]; then
                printf 'CPU %s°C\n' "$best"
                exit 0
            fi
            ;;
    esac
done

printf 'CPU --°C\n'

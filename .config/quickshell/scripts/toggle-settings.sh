#!/bin/sh

# Yakushi Qt palette for Settings and its non-native file picker.
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_STYLE_OVERRIDE=Fusion
export QT_QUICK_CONTROLS_STYLE=Fusion


# Yakushi Settings-only Qt Quick Controls theme.
# Required by the non-native Qt Quick file picker.


settings_qml="$HOME/.config/quickshell/settings-shell.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$(id -u)}/yakushi"
pid_file="$runtime_root/settings.pid"
log_file="$runtime_root/settings.log"     # your private runtime folder, not /tmp

mkdir -p -m 700 "$runtime_root"

# toggle-settings.sh [page]: with a page (e.g. tasks) it opens Settings on
# that page, or switches an open Settings to it
start_page="$1"

if [ -r "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null)"

    # only if that process really is Settings: a pid number can be reused by
    # another program after Settings has closed
    if [ -n "$pid" ] && grep -qa -- "settings-shell.qml" "/proc/$pid/cmdline" 2>/dev/null; then
        if [ -n "$start_page" ]; then
            timeout 2 qs -p "$settings_qml" ipc call settings open "$start_page" >/dev/null 2>&1 && exit 0
            kill -9 "$pid" 2>/dev/null          # it does not answer: start a fresh one
        else
            timeout 2 qs -p "$settings_qml" ipc call settings hide >/dev/null 2>&1 || kill -9 "$pid" 2>/dev/null
            exit 0
        fi
    fi

    rm -f "$pid_file"
fi

YAKUSHI_SETTINGS_PAGE="$start_page" qs -n -p "$settings_qml" >"$log_file" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$pid_file"

#!/bin/sh

# Yakushi Qt palette for Settings and its non-native file picker.
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_STYLE_OVERRIDE=Fusion
export QT_QUICK_CONTROLS_STYLE=Fusion


# Yakushi Settings-only Qt Quick Controls theme.
# Required by the non-native Qt Quick file picker.


settings_qml="$HOME/.config/quickshell/settings-shell.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$UID}/yakushi"
pid_file="$runtime_root/settings.pid"
log_file="/tmp/yakushi-settings.log"

mkdir -p "$runtime_root"

if [ -r "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        qs -p "$settings_qml" ipc call settings hide >/dev/null 2>&1 ||             kill "$pid" 2>/dev/null
        exit 0
    fi

    rm -f "$pid_file"
fi

qs -n -p "$settings_qml" >"$log_file" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$pid_file"

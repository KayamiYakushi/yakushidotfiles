import Quickshell
import Quickshell.Io
import QtQuick
import "topbar"

// Yakushi island top bar. Started by scripts/yakushi-bar.sh; configured in
// Settings (SUPER + I) -> Top Bar.
ShellRoot {
    id: root

    BarConfig {
        id: barConfig
    }

    SystemStats {
        id: barStats
        config: barConfig
    }

    MediaState {
        id: barMedia
        config: barConfig
    }

    // Bumped by the power shortcut (IPC); the bar on the focused monitor
    // opens its power menu.
    QtObject {
        id: barPower
        property int requests: 0
    }

    SystemClock {
        id: barClock

        // Tick once a second only when seconds are actually shown.
        precision: barConfig.seconds && barConfig.modules.time
            ? SystemClock.Seconds
            : SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        TopBar {
            required property var modelData

            screen: modelData
            config: barConfig
            stats: barStats
            clock: barClock
            media: barMedia
            power: barPower
        }
    }

    // Settings pings this after saving, so changes apply at once even if
    // the file watcher missed an atomic replace.
    IpcHandler {
        target: "topbar"

        function reload(): void {
            barConfig.reload()
        }

        function power(): void {
            barPower.requests += 1
        }
    }
}

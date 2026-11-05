import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    SettingsWindow {
        id: settingsWindow

        // toggle-settings.sh tasks -> opens on Tasks
        Component.onCompleted: show(Quickshell.env("YAKUSHI_SETTINGS_PAGE") || "")

        onDismissed: quitTimer.restart()
    }

    IpcHandler {
        target: "settings"

        function hide(): void {
            settingsWindow.hide()
        }

        function open(name: string): void {
            settingsWindow.show(name)
        }

        function toggle(): void {
            if (settingsWindow.showing)
                settingsWindow.hide()
            else
                settingsWindow.show()
        }
    }

    Timer {
        id: quitTimer
        interval: 450
        repeat: false
        onTriggered: Qt.quit()
    }
}

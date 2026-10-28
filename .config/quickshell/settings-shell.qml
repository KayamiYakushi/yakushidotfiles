import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    SettingsWindow {
        id: settingsWindow

        Component.onCompleted: show()

        onDismissed: quitTimer.restart()
    }

    IpcHandler {
        target: "settings"

        function hide(): void {
            settingsWindow.hide()
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

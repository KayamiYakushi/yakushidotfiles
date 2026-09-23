import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    VolumeOsd {
        id: osd
    }

    function showAndArmExit(): void {
        osd.showOsd()
        exitTimer.restart()
    }

    Component.onCompleted: showAndArmExit()

    IpcHandler {
        target: "volumeOsd"

        function show(): void {
            root.showAndArmExit()
        }
    }

    Timer {
        id: exitTimer
        interval: 1550
        repeat: false
        onTriggered: Qt.quit()
    }
}

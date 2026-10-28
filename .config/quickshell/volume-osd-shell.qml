import QtQuick
import Quickshell
import Quickshell.Io

// Short-lived shell for the volume pill: every "show" call keeps it alive
// a little longer, then it quits on its own.
ShellRoot {
    id: shell

    function bump() {
        pill.poke()
        quitLater.restart()
    }

    VolumeOsd {
        id: pill
    }

    Timer {
        id: quitLater
        interval: 1550
        onTriggered: Qt.quit()
    }

    IpcHandler {
        target: "volumeOsd"
        function show(): void { shell.bump() }
    }

    Component.onCompleted: bump()
}

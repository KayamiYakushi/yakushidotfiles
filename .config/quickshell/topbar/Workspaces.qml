import Quickshell.Hyprland
import QtQuick
import "../"

// Workspace dots. The active one stretches into an accent-coloured pill.
// Click a dot to switch, scroll to step through.
Item {
    id: ws

    required property var screen
    required property int barHeight

    signal activate(int id)

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor && monitor.activeWorkspace
        ? monitor.activeWorkspace.id
        : 1

    readonly property var occupied: {
        var set = {}
        var list = Hyprland.workspaces.values
        for (var i = 0; i < list.length; i++)
            if (list[i].id > 0)
                set[list[i].id] = true
        return set
    }

    readonly property int shown: {
        var count = 5
        var list = Hyprland.workspaces.values
        for (var i = 0; i < list.length; i++)
            if (list[i].id > count && list[i].id <= 10)
                count = list[i].id
        return Math.max(count, Math.min(activeId, 10))
    }

    implicitWidth: dots.implicitWidth
    implicitHeight: barHeight
    height: barHeight

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        acceptedButtons: Qt.NoButton

        onWheel: function(event) {
            var step = event.angleDelta.y > 0 ? -1 : 1
            var next = Math.max(1, Math.min(10, ws.activeId + step))
            if (next !== ws.activeId)
                ws.activate(next)
        }
    }

    Row {
        id: dots

        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Repeater {
            model: ws.shown

            delegate: Item {
                id: dot

                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: wsId === ws.activeId
                readonly property bool used: ws.occupied[wsId] === true

                width: active ? 20 : 7
                height: ws.barHeight

                Behavior on width {
                    NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: dotMouse.containsMouse && !dot.active ? 9 : 7
                    radius: height / 2
                    color: dot.active
                        ? Theme.accent
                        : dot.used
                            ? Theme.tint(Theme.ink, dotMouse.containsMouse ? 0.85 : 0.55)
                            : Theme.tint(Theme.ink, dotMouse.containsMouse ? 0.45 : 0.18)

                    Behavior on color {
                        ColorAnimation { duration: Theme.tFast }
                    }

                    Behavior on height {
                        NumberAnimation { duration: Theme.tFast }
                    }
                }

                MouseArea {
                    id: dotMouse

                    anchors.fill: parent
                    anchors.leftMargin: -2
                    anchors.rightMargin: -2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ws.activate(dot.wsId)
                }
            }
        }
    }
}

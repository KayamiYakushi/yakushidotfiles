import QtQuick
import "../"

// Icon + label + square-cornered switch, in the same visual language as the
// sliders. Emits `toggled` on click; the caller owns `checked`.
Item {
    id: row

    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool available: true

    signal toggled()

    implicitHeight: 28
    opacity: available ? 1.0 : 0.35

    Behavior on opacity {
        NumberAnimation { duration: Theme.tFast }
    }

    Text {
        id: iconText

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        text: row.icon
        color: Theme.accent
        font.family: Theme.glyphs
        font.pixelSize: 14
    }

    Text {
        anchors.left: iconText.right
        anchors.right: stateText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        elide: Text.ElideRight
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
        font.letterSpacing: 1
    }

    Text {
        id: stateText

        anchors.right: track.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: row.checked ? "ON" : "OFF"
        color: row.checked ? Theme.accent : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        font.letterSpacing: 2

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 16
        radius: Theme.corner
        color: row.checked ? Theme.tint(Theme.accent, 0.18) : Theme.groove
        border.width: 1
        border.color: row.checked
            ? Theme.accent
            : (mouse.containsMouse ? Theme.lineHot : Theme.line)

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.tFast }
        }

        Rectangle {
            width: 10
            height: 10
            radius: Theme.rounded ? (2) : 0
            anchors.verticalCenter: parent.verticalCenter
            x: row.checked ? parent.width - width - 3 : 3
            color: row.checked ? Theme.accent : Theme.inkSoft

            Behavior on x {
                NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic }
            }

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: row.available
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}

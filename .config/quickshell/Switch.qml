import QtQuick

// Square-cornered on/off switch with an ON/OFF label, matching ToggleRow.
// The caller owns `checked` and reacts to `toggled`.
Item {
    id: sw

    property bool checked: false
    property bool available: true

    signal toggled()

    implicitWidth: stateText.implicitWidth + 10 + track.width
    implicitHeight: 22
    opacity: available ? 1 : 0.4

    Text {
        id: stateText

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: sw.checked ? "ON" : "OFF"
        color: sw.checked ? Theme.accent : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        font.letterSpacing: 2
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 16
        radius: Theme.corner
        color: sw.checked ? Theme.tint(Theme.accent, 0.18) : Theme.groove
        border.width: 1
        border.color: sw.checked
            ? Theme.accent
            : (mouse.containsMouse ? Theme.lineHot : Theme.line)

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }

        Rectangle {
            width: 10
            height: 10
            radius: Theme.rounded ? (2) : 0
            anchors.verticalCenter: parent.verticalCenter
            x: 3 + (sw.checked ? parent.width - width - 6 : 0)
            color: sw.checked ? Theme.accent : Theme.inkSoft

            Behavior on x {
                NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        enabled: sw.available
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}

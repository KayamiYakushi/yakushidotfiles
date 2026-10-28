import QtQuick

// Bordered header button with an icon and a short label (Reload, Undo...).
Rectangle {
    id: hb

    property string label: ""
    property string icon: ""
    signal activated()

    width: hbRow.implicitWidth + 24
    height: 30
    radius: Theme.corner
    color: hbMouse.containsMouse ? Theme.tint(Theme.accent, 0.10) : "transparent"
    border.width: 1
    border.color: hbMouse.containsMouse ? Theme.tint(Theme.accent, 0.6) : Theme.line

    Row {
        id: hbRow

        anchors.centerIn: parent
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hb.icon
            color: hbMouse.containsMouse ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hb.label
            color: hbMouse.containsMouse ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }
    }

    MouseArea {
        id: hbMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: hb.activated()
    }
}

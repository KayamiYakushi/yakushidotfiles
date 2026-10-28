import QtQuick

// Small bordered square button with a single glyph. `busy` spins the glyph
// (only while busy, so it costs nothing otherwise).
Rectangle {
    id: btn

    property string glyph: ""
    property bool busy: false
    property bool available: true

    signal activated()

    width: 30
    height: 30
    radius: Theme.corner
    opacity: available ? 1 : 0.4
    color: mouse.containsMouse && available ? Theme.tint(Theme.accent, 0.10) : "transparent"
    border.width: 1
    border.color: mouse.containsMouse && available ? Theme.tint(Theme.accent, 0.6) : Theme.line

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.busy || (mouse.containsMouse && btn.available) ? Theme.accent : Theme.inkSoft
        font.family: Theme.glyphs
        font.pixelSize: 14

        RotationAnimation on rotation {
            running: btn.busy
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1200
        }

        rotation: 0
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.available
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}

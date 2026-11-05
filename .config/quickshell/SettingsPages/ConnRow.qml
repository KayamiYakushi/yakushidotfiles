import QtQuick
import "../"

// One row in Settings -> Network / Bluetooth: a glyph, a name, a detail line,
// a gear that opens its settings and one button (connect / disconnect).
Rectangle {
    id: row

    property string glyph: ""
    property string title: ""
    property string detail: ""
    property bool active: false          // connected: accent colours
    property bool open: false            // its settings (or password line) are open
    property bool gear: false            // show the settings button
    property string action: ""           // button text, "" = no button
    property bool danger: false          // the button disconnects
    property bool busy: false

    signal pressed()
    signal settings()

    height: 60
    color: active ? Theme.tint(Theme.accent, 0.12)
        : over.hovered ? Theme.tint(Theme.ink, 0.05) : Theme.card
    border.width: 1
    border.color: active || open ? Theme.accent : over.hovered ? Theme.lineHot : Theme.line

    Behavior on color {
        ColorAnimation { duration: Theme.tFast }
    }

    HoverHandler {
        id: over
    }

    Rectangle {
        id: badge

        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        color: row.active ? Theme.tint(Theme.accent, 0.18) : Theme.tint(Theme.ink, 0.05)

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: row.glyph
            color: row.active ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 17
        }
    }

    Text {
        id: name

        textFormat: Text.PlainText
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: tools.left
        anchors.rightMargin: 12
        anchors.bottom: parent.verticalCenter
        anchors.bottomMargin: 1
        text: row.title
        elide: Text.ElideRight
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
    }

    Text {
        textFormat: Text.PlainText
        anchors.left: name.left
        anchors.right: name.right
        anchors.top: parent.verticalCenter
        anchors.topMargin: 3
        text: row.detail
        elide: Text.ElideRight
        color: row.active ? Theme.accent : Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 9
    }

    Row {
        id: tools

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // settings of this connection
        Rectangle {
            visible: row.gear
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            color: row.open ? Theme.tint(Theme.accent, 0.18)
                : gearMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : "transparent"
            border.width: 1
            border.color: row.open ? Theme.accent : gearMouse.containsMouse ? Theme.lineHot : Theme.line

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF0493)
                color: row.open || gearMouse.containsMouse ? Theme.accent : Theme.inkSoft
                font.family: Theme.glyphs
                font.pixelSize: 13
            }

            MouseArea {
                id: gearMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.settings()
            }
        }

        Rectangle {
            visible: row.action !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: label.implicitWidth + 24
            height: 28
            opacity: row.busy ? 0.6 : 1
            color: row.danger
                ? (press.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
                : Theme.tint(Theme.accent, press.containsMouse ? 0.24 : 0.12)
            border.width: 1
            border.color: Theme.tint(row.danger ? Theme.alert : Theme.accent, 0.6)

            Text {
                id: label

                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: row.action
                color: row.danger ? Theme.alert : Theme.ink
                font.family: Theme.mono
                font.pixelSize: 9
                font.letterSpacing: 1
            }

            MouseArea {
                id: press

                anchors.fill: parent
                hoverEnabled: true
                enabled: !row.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: row.pressed()
            }
        }
    }
}

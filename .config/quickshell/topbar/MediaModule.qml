import QtQuick
import "../"

// Now playing, as shown in the bar row. Hovering it opens the media card
// (MediaCard.qml) that drops down from the island.
//
// Left click: play/pause - right click: next - middle click: previous
Item {
    id: m

    required property var media
    required property int barHeight

    // True while the card is open, so the module stays highlighted.
    property bool active: false

    readonly property var player: media.player
    readonly property bool hovered: hover.hovered
    readonly property bool inlineBars: media.config.visualizer === "always" && media.playing

    implicitWidth: row.implicitWidth
    implicitHeight: barHeight
    height: barHeight

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: m.media.playing ? String.fromCodePoint(0xF040A) : String.fromCodePoint(0xF03E4)
            color: m.hovered || m.active ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 13
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 240)
            text: m.media.trackText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: m.hovered || m.active ? Theme.accent : (m.media.playing ? Theme.ink : Theme.inkSoft)
            font.family: Theme.mono
            font.pixelSize: 11

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }
        }

        // Small inline bars when the visualizer is set to "always"
        Row {
            visible: m.inlineBars
            anchors.verticalCenter: parent.verticalCenter
            height: 12
            spacing: 2

            Repeater {
                model: m.inlineBars ? m.media.barCount : 0

                Rectangle {
                    required property int index

                    anchors.bottom: parent.bottom
                    width: 2.5
                    radius: 1.25
                    height: 2 + 10 * (m.media.levels[index] || 0)
                    color: Theme.accent
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: -5
        anchors.rightMargin: -5
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: function(event) {
            if (!m.player)
                return
            if (event.button === Qt.RightButton)
                m.player.next()
            else if (event.button === Qt.MiddleButton)
                m.player.previous()
            else
                m.player.togglePlaying()
        }
    }
}

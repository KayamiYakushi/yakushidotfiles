import Quickshell.Services.Pipewire
import QtQuick
import "../"

// Volume. Hover slides out a small slider (click or drag to set).
// Left click on the icon: mute - right click: mixer - wheel: +/- 5%
Item {
    id: v

    required property int barHeight

    signal openMixer()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real level: ready ? sink.audio.volume : 0
    readonly property int percent: Math.round(level * 100)
    readonly property bool muted: ready ? sink.audio.muted : false
    readonly property bool hovered: hover.hovered
    readonly property bool expanded: hovered || linger.running || drag.pressed

    function setLevel(value) {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(1, value))
    }

    implicitWidth: row.implicitWidth
    implicitHeight: barHeight
    height: barHeight

    PwObjectTracker {
        objects: [v.sink]
    }

    Timer {
        id: linger
        interval: 350
    }

    onHoveredChanged: if (!hovered) linger.restart()

    HoverHandler {
        id: hover
    }

    // Wheel anywhere on the module
    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: -5
        anchors.rightMargin: -5
        acceptedButtons: Qt.NoButton

        onWheel: function(event) {
            if (event.angleDelta.y === 0)
                return
            var next = v.level + (event.angleDelta.y > 0 ? 0.05 : -0.05)
            v.setLevel(Math.round(next * 20) / 20)
        }
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: v.muted
                ? String.fromCodePoint(0xF075F)
                : v.percent >= 60 ? String.fromCodePoint(0xF057E)
                : v.percent >= 25 ? String.fromCodePoint(0xF0580)
                : String.fromCodePoint(0xF057F)
            color: iconMouse.containsMouse ? Theme.accent : Theme.textDim
            font.family: Theme.iconFont
            font.pixelSize: 13

            MouseArea {
                id: iconMouse

                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onClicked: function(event) {
                    if (event.button === Qt.RightButton)
                        v.openMixer()
                    else if (v.ready)
                        v.sink.audio.muted = !v.sink.audio.muted
                }
            }
        }

        // Slider (hover only)
        Item {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: v.expanded ? 64 : 0
            height: 14
            visible: width > 0.5
            clip: true

            Behavior on width {
                NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 4
                radius: 2
                color: Theme.alpha(Theme.text, 0.14)

                Rectangle {
                    width: parent.width * Math.min(1, v.level)
                    height: parent.height
                    radius: 2
                    color: v.muted ? Theme.textDim : Theme.accent
                }

                Rectangle {
                    x: parent.width * Math.min(1, v.level) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.text
                }
            }

            MouseArea {
                id: drag

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                function apply(x) {
                    v.setLevel(Math.round(x / 64 * 100) / 100)
                }

                onPressed: function(event) { apply(event.x) }
                onPositionChanged: function(event) { if (pressed) apply(event.x) }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (v.percent < 10 ? " " : "") + v.percent + "%"
            textFormat: Text.PlainText
            color: v.muted ? Theme.textDim : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}

import Quickshell.Widgets
import QtQuick
import "../"

// The card the island grows into when the song is hovered:
// cover art, title and artist, a live visualizer, a seekable progress bar
// with elapsed / remaining time, and previous - play/pause - next.
//
// Nothing here runs while the card is closed: the position poll and the
// spectrum (cava) both stop with it.
Item {
    id: card

    required property var media
    property bool open: false

    readonly property var player: media.player
    readonly property real length: player && player.lengthSupported ? player.length : 0
    readonly property real position: player && player.positionSupported ? player.position : 0
    readonly property bool canSeek: player !== null && player.canSeek === true && length > 0
    readonly property bool showBars: media.config.visualizer !== "off" && media.playing

    // Ask MediaState for spectrum data only while the card is open.
    property bool asking: false

    function syncDemand() {
        var want = open && media.config.visualizer === "hover"
        if (want !== asking) {
            asking = want
            media.request(want)
        }
    }

    onOpenChanged: syncDemand()
    Component.onDestruction: if (asking) media.request(false)

    Connections {
        target: card.media.config
        function onVisualizerChanged() { card.syncDemand() }
    }

    function clock(seconds) {
        var s = Math.max(0, Math.floor(seconds))
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // MPRIS does not push position updates; poll once a second while open.
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: card.open && card.player !== null
        onTriggered: card.player.positionChanged()
    }

    // ---------------- Art + title + visualizer ----------------
    ClippingRectangle {
        id: art

        x: 0
        y: 0
        width: 52
        height: 52
        radius: 10
        color: Theme.trackBg

        Text {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            text: String.fromCodePoint(0xF075A)
            color: Theme.textFaint
            font.family: Theme.iconFont
            font.pixelSize: 22
        }

        Image {
            id: cover

            anchors.fill: parent
            source: card.open ? card.media.artUrl : ""
            sourceSize.width: 104
            sourceSize.height: 104
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 12
        anchors.right: bars.left
        anchors.rightMargin: 12
        anchors.verticalCenter: art.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: card.media.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: card.media.artist
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }

    Row {
        id: bars

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 4
        height: 18
        spacing: 2.5
        opacity: card.showBars ? 1 : 0.35

        Repeater {
            model: card.media.barCount

            Rectangle {
                required property int index

                anchors.bottom: parent.bottom
                width: 3
                radius: 1.5
                height: 3 + 15 * (card.showBars ? (card.media.levels[index] || 0) : 0)
                color: Theme.accent
            }
        }
    }

    // ---------------- Progress ----------------
    Item {
        id: progressRow

        anchors.left: parent.left
        anchors.right: parent.right
        y: art.height + 12
        height: 14
        visible: card.length > 0

        Text {
            id: elapsed

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: card.clock(card.position)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Text {
            id: remaining

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            horizontalAlignment: Text.AlignRight
            text: "-" + card.clock(card.length - card.position)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Item {
            id: track

            anchors.left: elapsed.right
            anchors.right: remaining.left
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: 14

            readonly property real ratio: Math.max(0, Math.min(1, card.position / Math.max(1, card.length)))

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: seekMouse.containsMouse ? 5 : 4
                radius: height / 2
                color: Theme.alpha(Theme.text, 0.14)

                Rectangle {
                    width: parent.width * track.ratio
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
            }

            MouseArea {
                id: seekMouse

                anchors.fill: parent
                hoverEnabled: true
                enabled: card.canSeek
                cursorShape: card.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

                onClicked: function(event) {
                    card.player.position = card.length * Math.max(0, Math.min(1, event.x / width))
                }
            }
        }
    }

    // ---------------- Controls ----------------
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: progressRow.y + progressRow.height + 8
        spacing: 30

        Repeater {
            model: [
                { action: "previous", glyph: 0xF045F, size: 20 },
                { action: "toggle", glyph: -1, size: 28 },
                { action: "next", glyph: 0xF0211, size: 20 }
            ]

            delegate: Text {
                id: control

                required property var modelData

                anchors.verticalCenter: parent.verticalCenter
                text: modelData.glyph > 0
                    ? String.fromCodePoint(modelData.glyph)
                    : String.fromCodePoint(card.media.playing ? 0xF03E4 : 0xF040A)
                color: controlMouse.containsMouse ? Theme.accent : Theme.text
                font.family: Theme.iconFont
                font.pixelSize: modelData.size
                scale: controlMouse.pressed ? 0.88 : 1

                Behavior on scale {
                    NumberAnimation { duration: 90 }
                }

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast }
                }

                MouseArea {
                    id: controlMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (!card.player)
                            return
                        if (control.modelData.action === "previous")
                            card.player.previous()
                        else if (control.modelData.action === "next")
                            card.player.next()
                        else
                            card.player.togglePlaying()
                    }
                }
            }
        }
    }
}

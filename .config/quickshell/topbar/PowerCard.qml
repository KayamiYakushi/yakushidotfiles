import Quickshell.Io
import QtQuick
import "../"

// Power menu that drops down from the island below the power button.
// Lock and Suspend act at once; Log out, Restart and Shut down ask for a
// second click (or Enter) within a few seconds, so a stray click is harmless.
//
// Keyboard (when opened with the shortcut): Left/Right or Tab to move,
// Enter/Space to choose, Esc to close.
Item {
    id: card

    property bool open: false

    signal run(var args)
    signal closeRequested()

    readonly property var actions: [
        { key: "lock",     label: "Lock",      glyph: 0xF033E, confirm: false,
          args: ["sh", "-c", "pidof hyprlock >/dev/null || exec hyprlock"] },
        { key: "suspend",  label: "Suspend",   glyph: 0xF04B2, confirm: false,
          args: ["systemctl", "suspend"] },
        { key: "logout",   label: "Log out",   glyph: 0xF0343, confirm: true,
          args: ["sh", "-c",
                 "out=$(hyprctl eval 'hl.dispatch(hl.dsp.exit())' 2>&1); "
                 + "case \"$out\" in *rror*|*nknown*|*nvalid*) hyprctl dispatch exit ;; esac"] },
        { key: "reboot",   label: "Restart",   glyph: 0xF0709, confirm: true,
          args: ["systemctl", "reboot"] },
        { key: "shutdown", label: "Shut down", glyph: 0xF0425, confirm: true,
          args: ["systemctl", "poweroff"] }
    ]

    property int focusIndex: -1
    property int armedIndex: -1
    property string uptime: ""

    function choose(index) {
        var action = actions[index]
        if (!action)
            return

        if (action.confirm && armedIndex !== index) {
            armedIndex = index
            disarm.restart()
            return
        }

        armedIndex = -1
        closeRequested()
        run(action.args)
    }

    onOpenChanged: {
        armedIndex = -1
        focusIndex = -1
        if (open) {
            uptimeFile.reload()
            keys.forceActiveFocus()
        }
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: card.armedIndex = -1
    }

    // Read once each time the menu opens.
    FileView {
        id: uptimeFile

        path: "/proc/uptime"
        printErrors: false

        onLoaded: {
            var secs = Math.floor(parseFloat(text()))
            if (isNaN(secs))
                return
            var d = Math.floor(secs / 86400)
            var h = Math.floor(secs % 86400 / 3600)
            var m = Math.floor(secs % 3600 / 60)
            card.uptime = "up " + (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m"
        }
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: card.open

        Keys.onPressed: function(event) {
            var n = card.actions.length
            if (event.key === Qt.Key_Escape) {
                card.closeRequested()
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                card.focusIndex = (card.focusIndex + 1 + n) % n
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
                card.focusIndex = card.focusIndex < 0 ? n - 1 : (card.focusIndex - 1 + n) % n
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (card.focusIndex >= 0)
                    card.choose(card.focusIndex)
            } else {
                return
            }
            event.accepted = true
        }
    }

    // ---------------- Header ----------------
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        height: 16

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: card.armedIndex >= 0
                ? "Click again to " + card.actions[card.armedIndex].label.toLowerCase()
                : "POWER"
            color: card.armedIndex >= 0 ? Theme.alert : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: card.armedIndex >= 0 ? 10 : 9
            font.letterSpacing: card.armedIndex >= 0 ? 0.5 : 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: card.uptime
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }
    }

    // ---------------- Tiles ----------------
    Row {
        id: tiles

        anchors.top: header.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Repeater {
            model: card.actions

            delegate: Rectangle {
                id: tile

                required property var modelData
                required property int index

                readonly property bool armed: card.armedIndex === index
                readonly property bool lit: tileMouse.containsMouse || card.focusIndex === index
                readonly property color tone: armed ? Theme.alert : Theme.accent

                width: Math.floor((card.width - 4 * tiles.spacing) / 5)
                height: 66
                radius: 14
                color: armed
                    ? Theme.tint(Theme.alert, 0.16)
                    : lit ? Theme.tint(Theme.accent, 0.12) : Theme.tint(Theme.ink, 0.045)
                border.width: 1
                border.color: armed
                    ? Theme.alert
                    : lit ? Theme.tint(Theme.accent, 0.7) : Theme.tint(Theme.ink, 0.06)
                scale: tileMouse.pressed ? 0.95 : 1

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Behavior on border.color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Behavior on scale {
                    NumberAnimation { duration: 90 }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(tile.modelData.glyph)
                        color: tile.armed || tile.lit ? tile.tone : Theme.ink
                        font.family: Theme.glyphs
                        font.pixelSize: 21

                        Behavior on color {
                            ColorAnimation { duration: Theme.tFast }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.armed ? "Sure?" : tile.modelData.label
                        color: tile.armed ? Theme.alert : (tile.lit ? Theme.ink : Theme.inkSoft)
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 0.5
                    }
                }

                // Countdown under an armed tile
                Rectangle {
                    visible: tile.armed
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 2
                    radius: 1
                    color: Theme.alert
                    width: tile.armed ? 0 : parent.width - 24

                    NumberAnimation on width {
                        running: tile.armed
                        from: tile.width - 24
                        to: 0
                        duration: 3000
                    }
                }

                MouseArea {
                    id: tileMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.choose(tile.index)
                }
            }
        }
    }
}

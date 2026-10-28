import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Network (Wi-Fi).
// Wi-Fi switch and a rescan button in the header; networks below, the
// connected one first. Secured networks ask for the password in a line
// that opens under them. scripts/yakushi-netctl.py talks to nmcli; this
// page calls it when opened and when you do something.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-netctl.py"

    property bool radio: true
    property var nets: []
    property bool busy: false
    property string asking: ""        // ssid whose password line is open
    property string note: ""

    // ---- one helper call at a time
    function call(args, busyText) {
        if (worker.running)
            return
        busy = true
        if (busyText)
            note = busyText
        worker.command = ["python3", helper].concat(args)
        worker.running = true
    }

    Process {
        id: worker

        stdout: StdioCollector {
            onStreamFinished: {
                page.busy = false
                try {
                    var d = JSON.parse(text)
                    page.radio = d.radio === true
                    page.nets = d.networks || []
                    page.note = d.message || ""
                    if (d.joined === true)
                        page.asking = ""
                } catch (e) {
                    page.note = "NetworkManager did not answer."
                }
            }
        }
    }

    Component.onCompleted: call(["state"])

    function press(net) {
        if (net.connected)
            call(["leave", net.ssid], "Disconnecting...")
        else if (net.secured)
            asking = asking === net.ssid ? "" : net.ssid
        else
            call(["join", net.ssid], "Connecting to " + net.ssid + "...")
    }

    function bars(signal) {
        return String.fromCodePoint(signal > 75 ? 0xF0928 : signal > 50 ? 0xF0925 : signal > 25 ? 0xF0922 : 0xF091F)
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    Item {
        id: head

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 48
        height: 28

        PageTitle {
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "NETWORK"
        }

        Row {
            id: actions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: String.fromCodePoint(0xF0450)
                busy: page.busy
                available: !page.busy && page.radio
                onActivated: page.call(["scan"], "Looking for networks...")
            }

            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: page.radio
                available: !page.busy
                onToggled: page.call(["radio", page.radio ? "off" : "on"],
                                     page.radio ? "Turning Wi-Fi off..." : "Turning Wi-Fi on...")
            }
        }
    }

    Rectangle {
        id: rule

        anchors.top: head.bottom
        anchors.topMargin: 12
        anchors.left: head.left
        anchors.right: head.right
        height: 1
        color: Theme.line
    }

    Text {
        id: noteLine

        anchors.top: rule.bottom
        anchors.topMargin: 10
        anchors.left: head.left
        anchors.right: head.right
        text: page.note !== "" ? page.note
            : !page.radio ? "Wi-Fi is off."
            : page.nets.length === 0 ? "No Wi-Fi networks found." : ""
        height: text === "" ? 0 : implicitHeight
        horizontalAlignment: Text.AlignHCenter
        color: page.note !== "" ? Theme.accent : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: page.note !== "" ? 10 : 12
        elide: Text.ElideRight
    }

    Flickable {
        id: scroller

        anchors.top: noteLine.bottom
        anchors.topMargin: 10
        anchors.left: head.left
        anchors.right: head.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: rows.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: rows

            width: scroller.width
            spacing: 6

            Repeater {
                model: page.nets

                delegate: Column {
                    id: entry

                    required property var modelData
                    readonly property bool open: page.asking === modelData.ssid

                    width: rows.width
                    spacing: 6

                    // ---- the network
                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: Theme.rounded ? 12 : 0
                        color: entry.modelData.connected ? Theme.tint(Theme.accent, 0.12)
                            : over.hovered ? Theme.tint(Theme.ink, 0.05) : Theme.card
                        border.width: 1
                        border.color: entry.modelData.connected || entry.open ? Theme.accent
                            : over.hovered ? Theme.lineHot : Theme.line

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
                            radius: Theme.rounded ? 10 : 0
                            color: entry.modelData.connected ? Theme.tint(Theme.accent, 0.18) : Theme.tint(Theme.ink, 0.05)

                            Text {
                                anchors.centerIn: parent
                                text: page.bars(entry.modelData.signal)
                                color: entry.modelData.connected ? Theme.accent : Theme.inkSoft
                                font.family: Theme.glyphs
                                font.pixelSize: 17
                            }
                        }

                        Text {
                            id: ssid

                            anchors.left: badge.right
                            anchors.leftMargin: 12
                            anchors.right: button.left
                            anchors.rightMargin: 12
                            anchors.bottom: parent.verticalCenter
                            anchors.bottomMargin: 1
                            text: entry.modelData.ssid
                            elide: Text.ElideRight
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.left: ssid.left
                            anchors.right: ssid.right
                            anchors.top: parent.verticalCenter
                            anchors.topMargin: 3
                            elide: Text.ElideRight
                            text: (entry.modelData.secured ? String.fromCodePoint(0xF033E) + " " : "")
                                + [entry.modelData.connected ? "Connected" : "",
                                   entry.modelData.secured ? "Secured" : "Open",
                                   entry.modelData.signal + "%"].filter(function(s) { return s !== "" }).join("  ·  ")
                            color: entry.modelData.connected ? Theme.accent : Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 9
                        }

                        Rectangle {
                            id: button

                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: buttonText.implicitWidth + 24
                            height: 28
                            radius: Theme.rounded ? 14 : 0
                            opacity: page.busy ? 0.6 : 1
                            color: entry.modelData.connected
                                ? (buttonMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
                                : Theme.tint(Theme.accent, buttonMouse.containsMouse ? 0.24 : 0.12)
                            border.width: 1
                            border.color: Theme.tint(entry.modelData.connected ? Theme.alert : Theme.accent, 0.6)

                            Text {
                                id: buttonText

                                anchors.centerIn: parent
                                text: entry.modelData.connected ? "DISCONNECT" : entry.open ? "CANCEL" : "CONNECT"
                                color: entry.modelData.connected ? Theme.alert : Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: buttonMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !page.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.press(entry.modelData)
                            }
                        }
                    }

                    // ---- password line (secured networks)
                    Rectangle {
                        visible: entry.open
                        width: parent.width
                        height: 44
                        radius: Theme.rounded ? 12 : 0
                        color: Theme.card
                        border.width: 1
                        border.color: secret.activeFocus ? Theme.accent : Theme.line

                        function join() {
                            page.call(["join", entry.modelData.ssid, secret.text], "Connecting to " + entry.modelData.ssid + "...")
                        }

                        Text {
                            id: key

                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF033E)
                            color: Theme.accent
                            font.family: Theme.glyphs
                            font.pixelSize: 13
                        }

                        TextInput {
                            id: secret

                            anchors.left: key.right
                            anchors.leftMargin: 12
                            anchors.right: joinButton.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            focus: entry.open
                            clip: true
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12

                            Keys.onReturnPressed: parent.join()
                            Keys.onEnterPressed: parent.join()
                            Keys.onEscapePressed: page.asking = ""

                            Text {
                                visible: secret.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password for " + entry.modelData.ssid
                                color: Theme.inkMute
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }

                        Rectangle {
                            id: joinButton

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: joinText.implicitWidth + 24
                            height: 28
                            radius: Theme.rounded ? 14 : 0
                            color: Theme.tint(Theme.accent, joinMouse.containsMouse ? 0.28 : 0.16)
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                id: joinText

                                anchors.centerIn: parent
                                text: "JOIN"
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: joinMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !page.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: parent.parent.join()
                            }
                        }
                    }
                }
            }
        }
    }
}

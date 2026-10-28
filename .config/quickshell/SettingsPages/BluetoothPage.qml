import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../"

// Settings -> Bluetooth.
// Power switch and a scan button in the header; nearby and known devices
// below, each with one button (connect / disconnect). Scanning runs only
// while this page is on screen and stops by itself after 30 seconds.
Item {
    id: page

    property var hostWindow: null

    readonly property var radio: Bluetooth.defaultAdapter
    readonly property bool powered: radio !== null && radio.enabled
    readonly property bool searching: radio !== null && radio.discovering

    // ---- short-lived message under the header
    property string note: ""

    function say(text) {
        note = text
        noteClear.restart()
    }

    Timer {
        id: noteClear
        interval: 3000
        onTriggered: page.note = ""
    }

    // ---- radio
    function search(wanted) {
        if (!powered)
            return
        radio.discovering = wanted && page.visible
    }

    function flipPower() {
        if (!radio)
            return
        var next = !radio.enabled
        if (!next)
            search(false)
        radio.enabled = next
        say(next ? "Turning Bluetooth on..." : "Turning Bluetooth off...")
    }

    function flipSearch() {
        if (!powered)
            return
        var next = !searching
        search(next)
        say(next ? "Looking for devices..." : "Stopped looking.")
    }

    // search while the page is shown and the radio is on
    onVisibleChanged: search(visible)
    onPoweredChanged: search(powered)
    Component.onCompleted: search(true)
    Component.onDestruction: search(false)

    Timer {
        // discovery keeps the radio busy: give up after 30 s
        interval: 30000
        running: page.searching
        onTriggered: page.search(false)
    }

    // ---- devices
    function nameOf(dev) {
        return dev.name || dev.address || "device"
    }

    function isState(dev, s) {
        return dev.state === s
    }

    function act(dev) {
        if (isState(dev, BluetoothDeviceState.Connected)) {
            say("Disconnecting " + nameOf(dev) + "...")
            dev.disconnect()
        } else if (isState(dev, BluetoothDeviceState.Disconnected)) {
            // BlueZ pairs as part of connecting; scanning at the same time
            // makes it answer "not ready", so stop that first.
            search(false)
            dev.trusted = true
            say("Connecting to " + nameOf(dev) + "...")
            dev.connect()
        }
    }

    function buttonText(dev) {
        return dev.pairing ? "PAIRING…"
            : isState(dev, BluetoothDeviceState.Connected) ? "DISCONNECT"
            : isState(dev, BluetoothDeviceState.Connecting) ? "CONNECTING…"
            : isState(dev, BluetoothDeviceState.Disconnecting) ? "DISCONNECTING…"
            : "CONNECT"
    }

    // icon name from BlueZ -> glyph
    readonly property var kinds: [
        ["headset", 0xF02CB], ["headphone", 0xF02CB], ["speaker", 0xF04C3], ["audio", 0xF04C3],
        ["keyboard", 0xF030C], ["mouse", 0xF037D], ["phone", 0xF011C], ["gaming", 0xF0297],
        ["joystick", 0xF0297], ["computer", 0xF0322]
    ]

    function glyphFor(iconName) {
        var n = String(iconName || "").toLowerCase()
        for (var i = 0; i < kinds.length; i++)
            if (n.indexOf(kinds[i][0]) >= 0)
                return String.fromCodePoint(kinds[i][1])
        return String.fromCodePoint(0xF00AF)
    }

    function detailOf(dev, linked) {
        var bits = []
        if (linked)
            bits.push("Connected")
        else if (dev.paired)
            bits.push("Paired")
        if (dev.batteryAvailable)
            bits.push(Math.round(dev.battery * 100) + "% battery")
        bits.push(dev.address)
        return bits.join("  ·  ")
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    Item {
        id: head

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 28
        height: 30

        PageTitle {
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "BLUETOOTH"
        }

        Row {
            id: actions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: String.fromCodePoint(0xF0450)
                busy: page.searching
                available: page.powered
                onActivated: page.flipSearch()
            }

            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: page.powered
                onToggled: page.flipPower()
            }
        }
    }

    Rectangle {
        id: rule

        anchors.top: head.bottom
        anchors.topMargin: 18
        anchors.left: head.left
        anchors.right: head.right
        height: 1
        color: Theme.line
    }

    Text {
        id: noteLine

        anchors.top: rule.bottom
        anchors.topMargin: page.note === "" ? 0 : 12
        anchors.left: head.left
        anchors.right: head.right
        height: page.note === "" ? 0 : implicitHeight
        visible: page.note !== ""
        text: page.note
        horizontalAlignment: Text.AlignHCenter
        color: Theme.accent
        font.family: Theme.mono
        font.pixelSize: 10
    }

    // big glyph + two lines, for "no adapter" / "off" / "nothing found"
    component Notice: Column {
        property string glyph: ""
        property string headline: ""
        property string hint: ""

        spacing: 8
        topPadding: 30

        Text {
            visible: parent.glyph !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.glyph
            color: Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 24
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.headline
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 1
        }

        Text {
            visible: parent.hint !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.hint
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
        }
    }

    Flickable {
        id: scroller

        anchors.top: noteLine.bottom
        anchors.topMargin: 18
        anchors.left: head.left
        anchors.right: head.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: devices.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: devices

            width: scroller.width
            spacing: 6

            Notice {
                visible: !page.radio
                anchors.horizontalCenter: parent.horizontalCenter
                headline: "NO BLUETOOTH ADAPTER"
            }

            Notice {
                visible: page.radio !== null && !page.powered
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: ""
                headline: "BLUETOOTH IS OFF"
                hint: "Turn it on to see devices."
            }

            Notice {
                visible: page.powered && deviceList.count === 0
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: ""
                headline: page.searching ? "LOOKING FOR DEVICES..." : "NO DEVICES FOUND"
                hint: page.searching ? "Keep this page open while devices appear." : "Press the refresh button to look again."
            }

            Repeater {
                id: deviceList

                model: page.radio ? page.radio.devices : null

                delegate: Rectangle {
                    id: row

                    required property BluetoothDevice modelData
                    readonly property bool linked: modelData.state === BluetoothDeviceState.Connected
                    readonly property bool working: modelData.pairing
                        || modelData.state === BluetoothDeviceState.Connecting
                        || modelData.state === BluetoothDeviceState.Disconnecting

                    width: devices.width
                    height: 60
                    radius: Theme.rounded ? 12 : 0
                    color: linked ? Theme.tint(Theme.accent, 0.12)
                        : over.hovered ? Theme.tint(Theme.ink, 0.05) : Theme.card
                    border.width: 1
                    border.color: linked ? Theme.accent : over.hovered ? Theme.lineHot : Theme.line

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
                        color: row.linked ? Theme.tint(Theme.accent, 0.18) : Theme.tint(Theme.ink, 0.05)

                        Text {
                            anchors.centerIn: parent
                            text: page.glyphFor(row.modelData.icon)
                            color: row.linked ? Theme.accent : Theme.inkSoft
                            font.family: Theme.glyphs
                            font.pixelSize: 17
                        }
                    }

                    Text {
                        id: title

                        anchors.left: badge.right
                        anchors.leftMargin: 12
                        anchors.right: button.left
                        anchors.rightMargin: 12
                        anchors.bottom: parent.verticalCenter
                        anchors.bottomMargin: 1
                        text: page.nameOf(row.modelData)
                        elide: Text.ElideRight
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.left: title.left
                        anchors.right: title.right
                        anchors.top: parent.verticalCenter
                        anchors.topMargin: 3
                        text: page.detailOf(row.modelData, row.linked)
                        elide: Text.ElideRight
                        color: row.linked ? Theme.accent : Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }

                    Rectangle {
                        id: button

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: label.implicitWidth + 24
                        height: 28
                        radius: Theme.rounded ? 14 : 0
                        opacity: row.working ? 0.6 : 1
                        color: row.linked
                            ? (press.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
                            : Theme.tint(Theme.accent, press.containsMouse ? 0.24 : 0.12)
                        border.width: 1
                        border.color: Theme.tint(row.linked ? Theme.alert : Theme.accent, 0.6)

                        Text {
                            id: label

                            anchors.centerIn: parent
                            text: page.buttonText(row.modelData)
                            color: row.linked ? Theme.alert : Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            id: press

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !row.working
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.act(row.modelData)
                        }
                    }
                }
            }
        }
    }
}

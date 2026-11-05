import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../"

// Settings -> Bluetooth.
// Power switch and a scan button in the header. Below, three groups:
// CONNECTED, MY DEVICES (paired before) and NEARBY (found by the scan), each
// device with one button (connect / disconnect); the gear of a paired one
// shows its battery and address, auto-connect, and FORGET. Scanning runs only
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
    property string opened: ""          // address whose details are open

    function listOf() {
        var m = radio ? radio.devices : null
        if (!m)
            return []
        // an ObjectModel has a `values` list; a plain list has Array's values()
        var v = m.values
        return v !== undefined && typeof v !== "function" ? v : m
    }

    // "connected" | "mine" | "nearby"
    function groupOf(dev) {
        if (dev.state === BluetoothDeviceState.Connected || dev.state === BluetoothDeviceState.Disconnecting)
            return "connected"
        return dev.paired || dev.bonded ? "mine" : "nearby"
    }

    // how many in each group (re-evaluated when a device changes state)
    readonly property var counts: {
        var c = { connected: 0, mine: 0, nearby: 0 }
        var list = listOf()
        for (var i = 0; i < list.length; i++)
            c[groupOf(list[i])]++
        return c
    }

    function forget(dev) {
        say("Forgot " + nameOf(dev) + ".")
        opened = ""
        dev.forget()
    }

    function kindOf(iconName) {
        var n = String(iconName || "").toLowerCase()
        var names = [["headset", "Headset"], ["headphone", "Headphones"], ["speaker", "Speaker"], ["audio", "Audio"],
                     ["keyboard", "Keyboard"], ["mouse", "Mouse"], ["phone", "Phone"], ["gaming", "Game controller"],
                     ["joystick", "Game controller"], ["computer", "Computer"], ["tablet", "Tablet"]]
        for (var i = 0; i < names.length; i++)
            if (n.indexOf(names[i][0]) >= 0)
                return names[i][1]
        return "Device"
    }

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

        textFormat: Text.PlainText
        anchors.top: rule.bottom
        anchors.topMargin: page.note === "" ? 0 : 12
        anchors.left: head.left
        anchors.right: head.right
        height: page.note === "" ? 0 : 14
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
            textFormat: Text.PlainText
            visible: parent.glyph !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.glyph
            color: Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 24
        }

        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.headline
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 1
        }

        Text {
            textFormat: Text.PlainText
            visible: parent.hint !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.hint
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
        }
    }

    // "CONNECTED · 2", with a little room above
    component GroupTitle: Item {
        property string label: ""
        property int count: 0
        property string hint: ""

        height: 36

        Text {
            id: groupLabel

            textFormat: Text.PlainText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            text: parent.label + "  ·  " + parent.count
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.baseline: groupLabel.baseline
            text: parent.hint
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
        }
    }

    component Fact: Column {
        property string key: ""
        property string value: ""

        spacing: 3

        Text {
            textFormat: Text.PlainText
            text: parent.key
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: parent.value !== "" ? parent.value : "—"
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
        }
    }

    // one device: its row and, for paired ones, the details under it
    component DeviceEntry: Column {
        id: entry

        required property BluetoothDevice modelData
        property string group: ""
        property var host: null              // the page: inline components do not see its id

        readonly property bool linked: modelData.state === BluetoothDeviceState.Connected
        readonly property bool working: modelData.pairing
            || modelData.state === BluetoothDeviceState.Connecting
            || modelData.state === BluetoothDeviceState.Disconnecting
        readonly property bool known: modelData.paired || modelData.bonded
        readonly property bool open: known && host.opened === modelData.address

        visible: host !== null && host.groupOf(modelData) === group
        width: parent ? parent.width : 0
        spacing: 6

        ConnRow {
            width: parent.width
            glyph: host.glyphFor(entry.modelData.icon)
            title: host.nameOf(entry.modelData)
            detail: host.detailOf(entry.modelData, entry.linked)
            active: entry.linked
            open: entry.open
            gear: entry.known
            action: host.buttonText(entry.modelData)
            danger: entry.linked
            busy: entry.working
            onPressed: host.act(entry.modelData)
            onSettings: host.opened = entry.open ? "" : entry.modelData.address
        }

        Rectangle {
            visible: entry.open
            width: parent.width
            height: visible ? details.implicitHeight + 28 : 0
            color: Theme.card
            border.width: 1
            border.color: Theme.line

            Column {
                id: details

                x: 14
                y: 14
                width: parent.width - 28
                spacing: 12

                // battery, when the device tells it
                Item {
                    visible: entry.modelData.batteryAvailable
                    width: parent.width
                    height: 26

                    Text {
                        id: batteryLabel

                        textFormat: Text.PlainText
                        text: "BATTERY"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 8
                        font.letterSpacing: 2
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.baseline: batteryLabel.baseline
                        text: Math.round(entry.modelData.battery * 100) + "%"
                        color: entry.modelData.battery < 0.2 ? Theme.alert : Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 4
                        color: Theme.groove

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, entry.modelData.battery))
                            height: parent.height
                            radius: parent.radius
                            color: entry.modelData.battery < 0.2 ? Theme.alert : Theme.accent
                        }
                    }
                }

                Grid {
                    id: facts

                    width: parent.width
                    columns: width > 540 ? 4 : 2
                    columnSpacing: 16
                    rowSpacing: 10

                    readonly property real cell: (width - columnSpacing * (columns - 1)) / columns

                    Fact { width: facts.cell; key: "TYPE"; value: host.kindOf(entry.modelData.icon) }
                    Fact { width: facts.cell; key: "ADDRESS"; value: entry.modelData.address }
                    Fact { width: facts.cell; key: "STATUS"; value: entry.linked ? "Connected" : "Paired, not connected" }
                    Fact { width: facts.cell; key: "NAME ON DEVICE"; value: entry.modelData.deviceName || entry.modelData.name || "" }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.line
                }

                Item {
                    width: parent.width
                    height: 22

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CONNECT AUTOMATICALLY"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    Switch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: entry.modelData.trusted
                        onToggled: entry.modelData.trusted = !entry.modelData.trusted
                    }
                }

                Item {
                    width: parent.width
                    height: 28

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: forgetButton.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: entry.modelData.trusted ? "It reconnects by itself when it is near and on."
                            : "It connects only when you press CONNECT."
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }

                    Rectangle {
                        id: forgetButton

                        anchors.right: parent.right
                        width: forgetText.implicitWidth + 26
                        height: 28
                        color: forgetMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent"
                        border.width: 1
                        border.color: Theme.tint(Theme.alert, 0.6)

                        Text {
                            id: forgetText

                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "FORGET DEVICE"
                            color: Theme.alert
                            font.family: Theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            id: forgetMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.forget(entry.modelData)
                        }
                    }
                }
            }
        }
    }

    ScrollHint {
        flick: scroller
    }

    Flickable {
        id: scroller

        anchors.top: noteLine.bottom
        anchors.topMargin: 6
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
                glyph: String.fromCodePoint(0xF00B2)
                headline: "BLUETOOTH IS OFF"
                hint: "Turn it on to see devices."
            }

            // ---- connected now
            GroupTitle {
                visible: page.powered && page.counts.connected > 0
                width: devices.width
                label: "CONNECTED"
                count: page.counts.connected
            }

            Repeater {
                model: page.powered && page.radio ? page.radio.devices : null
                delegate: DeviceEntry { group: "connected"; host: page }
            }

            // ---- paired before
            GroupTitle {
                visible: page.powered && page.counts.mine > 0
                width: devices.width
                label: "MY DEVICES"
                count: page.counts.mine
                hint: "paired before"
            }

            Repeater {
                model: page.powered && page.radio ? page.radio.devices : null
                delegate: DeviceEntry { group: "mine"; host: page }
            }

            // ---- found by the scan
            GroupTitle {
                visible: page.powered && (page.counts.nearby > 0 || page.searching)
                width: devices.width
                label: "NEARBY"
                count: page.counts.nearby
                hint: page.searching ? "looking…" : "press refresh to look again"
            }

            Repeater {
                model: page.powered && page.radio ? page.radio.devices : null
                delegate: DeviceEntry { group: "nearby"; host: page }
            }

            Notice {
                visible: page.powered && page.counts.connected + page.counts.mine + page.counts.nearby === 0
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: String.fromCodePoint(0xF00AF)
                headline: page.searching ? "LOOKING FOR DEVICES..." : "NO DEVICES FOUND"
                hint: page.searching ? "Keep this page open while devices appear." : "Press the refresh button to look again."
            }

            Item {
                width: devices.width
                height: 12
            }
        }
    }
}

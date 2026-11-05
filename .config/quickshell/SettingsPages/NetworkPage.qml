import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Network: Ethernet and Wi-Fi.
// On top, the connection the internet goes through, how much it moves right
// now and a speed test (with the average of the last tests). Below, the
// cables and the Wi-Fi networks; the gear on a connection opens its settings
// (DNS, IP address, auto-connect, forget). scripts/yakushi-netctl.py talks to
// nmcli; this page calls it when opened, when you do something and every
// 20 s while it is on screen. The live rates read two files in /sys, so they
// spawn nothing.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-netctl.py"

    property bool radio: true
    property string wifiDevice: ""
    property var wired: []
    property var nets: []
    property var primary: null
    property bool loaded: false
    property bool busy: false
    property string asking: ""        // ssid whose password line is open
    property string opened: ""        // uuid whose settings are open
    property string note: ""

    // ---- one helper call at a time
    property bool again: false        // a refresh asked for while busy
    property var queued: null         // an action pressed while busy: runs next
    property string pending: ""       // a Wi-Fi password on its way (stdin, never a command line)

    function call(args, busyText, password) {
        if (worker.running) {
            if (args[0] === "state")
                again = true
            else
                queued = { args: args, busyText: busyText, password: password || "" }
            return
        }
        busy = true
        if (busyText) {
            note = busyText
            noteClear.stop()
        }
        pending = password || ""
        worker.stdinEnabled = pending !== ""
        worker.command = ["python3", helper].concat(pending !== "" ? ["--password-stdin"] : []).concat(args)
        worker.running = true
    }

    // assign only when it changed, so open settings are not rebuilt
    function update(name, value) {
        if (JSON.stringify(page[name]) !== JSON.stringify(value))
            page[name] = value
    }

    Process {
        id: worker

        onStarted: {
            if (stdinEnabled) {
                worker.write(page.pending + "\n")
                page.pending = ""
                stdinEnabled = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                page.busy = false
                try {
                    var d = JSON.parse(text)
                    page.radio = d.radio === true
                    page.wifiDevice = d.wifiDevice || ""
                    page.update("wired", d.wired || [])
                    page.update("nets", d.networks || [])
                    page.update("primary", d.primary || null)
                    page.loaded = true
                    if (d.message !== undefined)
                        page.say(d.message)
                    else if (page.note.endsWith("..."))
                        page.note = ""
                    if (d.joined === true)
                        page.asking = ""
                } catch (e) {
                    page.note = "NetworkManager did not answer."
                }
            }
        }

        onRunningChanged: {
            if (running)
                return
            if (page.queued !== null) {
                var next = page.queued
                page.queued = null
                Qt.callLater(function() { page.call(next.args, next.busyText, next.password) })
            } else if (page.again) {
                page.again = false
                Qt.callLater(function() { page.call(["state"]) })
            }
        }
    }

    Component.onCompleted: {
        call(["state"])
        speedCall(["speed"])
    }

    Timer {
        interval: 20000
        repeat: true
        running: page.visible && page.loaded
        onTriggered: {
            if (!worker.running && page.asking === "")
                page.call(["state"])
        }
    }

    // ---- actions
    function pressWifi(net) {
        if (net.connected)
            call(["down", net.uuid], "Disconnecting...")
        else if (net.known)
            call(["up", net.uuid], "Connecting to " + net.ssid + "...")
        else if (net.secured)
            asking = asking === net.ssid ? "" : net.ssid
        else
            call(["join", net.ssid], "Connecting to " + net.ssid + "...")
    }

    function pressWired(w) {
        call(["wired", w.device, w.connected ? "down" : "up"], w.connected ? "Disconnecting the cable..." : "Connecting the cable...")
    }

    function toggleSettings(uuid) {
        asking = ""
        opened = opened === uuid ? "" : uuid
    }

    // a result: shown for a while, then the line goes away
    function say(text) {
        note = text
        noteClear.restart()
    }

    Timer {
        id: noteClear
        interval: 6000
        onTriggered: page.note = ""
    }

    function settingsChanged(message) {
        say(message)
        call(["state"])
    }

    function bars(signal) {
        return String.fromCodePoint(signal > 75 ? 0xF0928 : signal > 50 ? 0xF0925 : signal > 25 ? 0xF0922 : 0xF091F)
    }

    function wiredDetail(w) {
        if (!w.cable && !w.connected)
            return "Cable unplugged"
        var bits = [w.connected ? "Connected" : w.state === "connecting" ? "Connecting" : "Not connected"]
        if (w.speed)
            bits.push(w.speed >= 1000 ? (w.speed / 1000) + " Gb/s" : w.speed + " Mb/s")
        if (w.ip)
            bits.push(w.ip)
        bits.push(w.device)
        return bits.join("  ·  ")
    }

    function wifiDetail(net) {
        var bits = []
        if (net.connected)
            bits.push("Connected")
        else if (net.known)
            bits.push("Saved")
        bits.push(net.secured ? "Secured" : "Open")
        bits.push(net.signal + "%")
        if (net.connected && net.rate)
            bits.push(net.rate.replace("Mbit/s", "Mb/s"))
        return (net.secured ? String.fromCodePoint(0xF033E) + " " : "") + bits.join("  ·  ")
    }

    // ---- live traffic of the connection the internet goes through
    readonly property string liveDevice: primary && primary.device ? primary.device : ""
    property real rxRate: -1           // bytes per second
    property real txRate: -1
    property real lastRx: -1
    property real lastTx: -1
    property real lastAt: 0
    property real pendingRx: -1

    function resetRates() {
        lastRx = -1
        rxRate = -1
        txRate = -1
    }

    onLiveDeviceChanged: resetRates()
    onVisibleChanged: resetRates()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: page.visible && page.liveDevice !== ""
        onTriggered: {
            rxFile.reload()
            txFile.reload()
        }
    }

    FileView {
        id: rxFile

        path: page.liveDevice !== "" ? "/sys/class/net/" + page.liveDevice + "/statistics/rx_bytes" : ""
        printErrors: false
        onLoaded: page.pendingRx = Number(text().trim())
    }

    FileView {
        id: txFile

        path: page.liveDevice !== "" ? "/sys/class/net/" + page.liveDevice + "/statistics/tx_bytes" : ""
        printErrors: false
        onLoaded: {
            var tx = Number(text().trim())
            var rx = page.pendingRx
            var now = Date.now()
            if (isNaN(tx) || isNaN(rx) || rx < 0)
                return
            if (page.lastRx >= 0 && now > page.lastAt) {
                var s = (now - page.lastAt) / 1000
                var r = Math.max(0, (rx - page.lastRx) / s)
                var t = Math.max(0, (tx - page.lastTx) / s)
                // a little smoothing so the numbers are readable
                page.rxRate = page.rxRate < 0 ? r : page.rxRate * 0.4 + r * 0.6
                page.txRate = page.txRate < 0 ? t : page.txRate * 0.4 + t * 0.6
            }
            page.lastRx = rx
            page.lastTx = tx
            page.lastAt = now
        }
    }

    function rate(bytes) {
        if (bytes < 0)
            return "—"
        var bits = bytes * 8
        if (bits >= 1e9)
            return (bits / 1e9).toFixed(2) + " Gb/s"
        if (bits >= 1e6)
            return (bits / 1e6).toFixed(1) + " Mb/s"
        return Math.round(bits / 1e3) + " kb/s"
    }

    // ---- speed test
    property var lastTest: null
    property var average: null
    property string speedNote: ""
    property int testSeconds: 0

    function speedCall(args) {
        if (speedJob.running)
            return
        speedJob.command = ["python3", helper].concat(args)
        speedJob.running = true
        if (args[0] === "speedtest") {
            testSeconds = 0
            speedNote = ""
        }
    }

    Process {
        id: speedJob

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    page.lastTest = d.last || null
                    page.average = d.average || null
                    page.speedNote = d.ok === false ? (d.message || "The speed test failed.") : ""
                } catch (e) {
                    page.speedNote = "The speed test failed."
                }
            }
        }
    }

    readonly property bool testing: speedJob.running && speedJob.command[2] === "speedtest"

    Timer {
        interval: 1000
        repeat: true
        running: page.testing
        onTriggered: page.testSeconds++
    }

    function mbit(v) {
        return v >= 100 ? Math.round(v).toString() : Number(v).toFixed(1)
    }

    function ago(t) {
        var s = Math.max(0, Date.now() / 1000 - t)
        return s < 90 ? "just now" : s < 5400 ? Math.round(s / 60) + " min ago"
            : s < 129600 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " days ago"
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
            anchors.right: refresh.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "NETWORK"
        }

        IconButton {
            id: refresh

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: String.fromCodePoint(0xF0450)
            busy: page.busy
            available: !page.busy
            onActivated: page.call([page.radio && page.wifiDevice !== "" ? "scan" : "state"], "Looking again...")
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
        anchors.topMargin: text === "" ? 0 : 10
        anchors.left: head.left
        anchors.right: head.right
        text: page.note
        height: text === "" ? 0 : 14
        horizontalAlignment: Text.AlignHCenter
        color: Theme.accent
        font.family: Theme.mono
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    component SectionTitle: Text {
        textFormat: Text.PlainText
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    component Stat: Column {
        property string key: ""
        property string value: "—"
        property string unit: ""

        spacing: 2

        Text {
            textFormat: Text.PlainText
            text: parent.key
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
            font.letterSpacing: 2
        }

        Row {
            spacing: 4

            Text {
                textFormat: Text.PlainText
                text: parent.parent.value
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 20
            }

            Text {
                textFormat: Text.PlainText
                anchors.baseline: parent.children[0].baseline
                text: parent.parent.unit
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
            }
        }
    }

    ScrollHint {
        flick: scroller
    }

    Flickable {
        id: scroller

        anchors.top: noteLine.bottom
        anchors.topMargin: 14
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

            // ================= now: connection, traffic, speed test =================
            Rectangle {
                id: status

                width: rows.width
                height: 118
                color: Theme.card
                border.width: 1
                border.color: page.primary ? Theme.tint(Theme.accent, 0.5) : Theme.line

                readonly property bool wide: width > 560
                readonly property bool viaWifi: page.primary !== null && page.primary.type === "wifi"

                // left: where the internet comes from
                Item {
                    id: via

                    x: 16
                    y: 16
                    width: status.wide ? status.width * 0.42 : status.width - 32
                    height: parent.height - 32

                    Rectangle {
                        id: viaBadge

                        width: 40
                        height: 40
                        color: page.primary ? Theme.tint(Theme.accent, 0.18) : Theme.tint(Theme.ink, 0.05)

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: !page.primary ? String.fromCodePoint(0xF0318)
                                : status.viaWifi ? page.bars(page.primary.signal || 0)
                                : String.fromCodePoint(0xF0200)
                            color: page.primary ? Theme.accent : Theme.inkSoft
                            font.family: Theme.glyphs
                            font.pixelSize: 19
                        }
                    }

                    Text {
                        id: viaKind

                        textFormat: Text.PlainText
                        anchors.left: viaBadge.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        y: 2
                        text: !page.loaded ? "…" : !page.primary ? "OFFLINE"
                            : (status.viaWifi ? "WI-FI" : page.primary.type === "ethernet" ? "ETHERNET" : "CONNECTED")
                        color: page.primary ? Theme.accent : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 3
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: viaKind.left
                        anchors.right: parent.right
                        anchors.top: viaKind.bottom
                        anchors.topMargin: 4
                        elide: Text.ElideRight
                        text: page.primary ? page.primary.name : "No connection carries the internet."
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: page.primary ? 13 : 10
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        elide: Text.ElideRight
                        visible: page.primary !== null
                        text: "NOW   ↓ " + page.rate(page.rxRate) + "   ↑ " + page.rate(page.txRate)
                            + (page.primary && page.primary.speed ? "   ·   link " + page.primary.speed.replace("Mbit/s", "Mb/s") : "")
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }
                }

                // right: speed test
                Item {
                    visible: status.wide
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    y: 16
                    width: status.width * 0.58 - 40
                    height: parent.height - 32

                    Rectangle {
                        x: -16
                        width: 1
                        height: parent.height
                        color: Theme.line
                    }

                    Row {
                        id: stats

                        spacing: 22

                        Stat {
                            key: "DOWNLOAD"
                            value: page.testing ? "…" : page.lastTest ? page.mbit(page.lastTest.down) : "—"
                            unit: "Mb/s"
                        }

                        Stat {
                            key: "UPLOAD"
                            value: page.testing ? "…" : page.lastTest ? page.mbit(page.lastTest.up) : "—"
                            unit: "Mb/s"
                        }

                        Stat {
                            key: "PING"
                            value: page.testing ? "…" : page.lastTest ? Math.round(page.lastTest.ping).toString() : "—"
                            unit: "ms"
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: testButton.left
                        anchors.rightMargin: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 7
                        elide: Text.ElideRight
                        text: page.testing ? "Testing… " + page.testSeconds + " s (about 20)"
                            : page.speedNote !== "" ? page.speedNote
                            : page.average && page.average.count > 1
                                ? "AVG of " + page.average.count + "   ↓ " + page.mbit(page.average.down) + "  ↑ " + page.mbit(page.average.up) + " Mb/s  ·  " + Math.round(page.average.ping) + " ms"
                            : page.lastTest ? "Tested " + page.ago(page.lastTest.time) + "."
                            : "Not tested yet."
                        color: page.speedNote !== "" ? Theme.alert : Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }

                    Rectangle {
                        id: testButton

                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: testText.implicitWidth + 24
                        height: 28
                        opacity: page.primary && !page.testing ? 1 : 0.5
                        color: Theme.tint(Theme.accent, testMouse.containsMouse && !page.testing ? 0.26 : 0.12)
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.7)

                        Text {
                            id: testText

                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: page.testing ? "TESTING…" : "TEST SPEED"
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            id: testMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.primary !== null && !page.testing
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.speedCall(["speedtest"])
                        }
                    }
                }
            }

            // narrow window: the speed test gets its own line
            Rectangle {
                visible: !status.wide
                width: rows.width
                height: 44
                color: Theme.card
                border.width: 1
                border.color: Theme.line

                Text {
                    textFormat: Text.PlainText
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: narrowTest.left
                    anchors.rightMargin: 12
                    elide: Text.ElideRight
                    text: page.testing ? "Testing… " + page.testSeconds + " s"
                        : page.lastTest ? "↓ " + page.mbit(page.lastTest.down) + "  ↑ " + page.mbit(page.lastTest.up) + " Mb/s  ·  " + Math.round(page.lastTest.ping) + " ms"
                            + (page.average && page.average.count > 1 ? "   (avg ↓ " + page.mbit(page.average.down) + ")" : "")
                        : "Speed: not tested yet."
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                }

                Rectangle {
                    id: narrowTest

                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: narrowText.implicitWidth + 24
                    height: 28
                    opacity: page.primary && !page.testing ? 1 : 0.5
                    color: Theme.tint(Theme.accent, 0.12)
                    border.width: 1
                    border.color: Theme.tint(Theme.accent, 0.7)

                    Text {
                        id: narrowText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: page.testing ? "TESTING…" : "TEST SPEED"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: page.primary !== null && !page.testing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.speedCall(["speedtest"])
                    }
                }
            }

            // ================= Ethernet =================
            Item {
                visible: page.wired.length > 0
                width: rows.width
                height: 40

                SectionTitle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: "ETHERNET"
                }
            }

            Repeater {
                model: page.wired

                delegate: Column {
                    id: cable

                    required property var modelData
                    readonly property bool open: page.opened !== "" && page.opened === modelData.uuid

                    width: rows.width
                    spacing: 6

                    ConnRow {
                        width: parent.width
                        glyph: String.fromCodePoint(cable.modelData.cable || cable.modelData.connected ? 0xF0200 : 0xF0202)
                        title: cable.modelData.connection || cable.modelData.device
                        detail: page.wiredDetail(cable.modelData)
                        active: cable.modelData.connected
                        open: cable.open
                        gear: cable.modelData.uuid !== ""
                        action: cable.modelData.connected ? "DISCONNECT" : cable.modelData.cable ? "CONNECT" : ""
                        danger: cable.modelData.connected
                        busy: page.busy
                        onPressed: page.pressWired(cable.modelData)
                        onSettings: page.toggleSettings(cable.modelData.uuid)
                    }

                    Loader {
                        active: cable.open
                        visible: active
                        width: parent.width

                        sourceComponent: NetConnPanel {
                            width: cable.width
                            uuid: cable.modelData.uuid
                            helper: page.helper
                            link: cable.modelData.speed ? cable.modelData.speed + " Mb/s" : ""
                            onSaved: message => page.settingsChanged(message)
                        }
                    }
                }
            }

            // ================= Wi-Fi =================
            Item {
                visible: page.wifiDevice !== ""
                width: rows.width
                height: 40

                SectionTitle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: "WI-FI"
                }

                Switch {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    checked: page.radio
                    available: !page.busy
                    onToggled: page.call(["radio", page.radio ? "off" : "on"],
                                         page.radio ? "Turning Wi-Fi off..." : "Turning Wi-Fi on...")
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: page.loaded && page.wifiDevice !== "" && (!page.radio || page.nets.length === 0)
                width: rows.width
                topPadding: 6
                bottomPadding: 6
                horizontalAlignment: Text.AlignHCenter
                text: !page.radio ? "Wi-Fi is off." : "No Wi-Fi networks found."
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Text {
                textFormat: Text.PlainText
                visible: page.loaded && page.wifiDevice === "" && page.wired.length === 0
                width: rows.width
                topPadding: 20
                horizontalAlignment: Text.AlignHCenter
                text: "NetworkManager sees no Ethernet port and no Wi-Fi card."
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Repeater {
                model: page.nets

                delegate: Column {
                    id: entry

                    required property var modelData
                    readonly property bool asked: page.asking === modelData.ssid
                    readonly property bool open: modelData.known && page.opened === modelData.uuid

                    width: rows.width
                    spacing: 6

                    ConnRow {
                        width: parent.width
                        glyph: page.bars(entry.modelData.signal)
                        title: entry.modelData.ssid
                        detail: page.wifiDetail(entry.modelData)
                        active: entry.modelData.connected
                        open: entry.open || entry.asked
                        gear: entry.modelData.known
                        action: entry.modelData.connected ? "DISCONNECT" : entry.asked ? "CANCEL" : "CONNECT"
                        danger: entry.modelData.connected
                        busy: page.busy
                        onPressed: page.pressWifi(entry.modelData)
                        onSettings: page.toggleSettings(entry.modelData.uuid)
                    }

                    Loader {
                        active: entry.open
                        visible: active
                        width: parent.width

                        sourceComponent: NetConnPanel {
                            width: entry.width
                            uuid: entry.modelData.uuid
                            helper: page.helper
                            canForget: true
                            link: entry.modelData.rate ? entry.modelData.rate.replace("Mbit/s", "Mb/s") : ""
                            onSaved: message => page.settingsChanged(message)
                        }
                    }

                    // ---- password line (new secured networks)
                    Rectangle {
                        visible: entry.asked
                        width: parent.width
                        height: 44

                        // type right away: the line takes the keyboard when it opens
                        onVisibleChanged: if (visible) Qt.callLater(function() { secret.forceActiveFocus() })
                        color: Theme.card
                        border.width: 1
                        border.color: secret.activeFocus ? Theme.accent : Theme.line

                        function join() {
                            if (secret.text === "")
                                return
                            page.call(["join", entry.modelData.ssid], "Connecting to " + entry.modelData.ssid + "...", secret.text)
                            secret.text = ""
                        }

                        Text {
                            id: key

                            textFormat: Text.PlainText
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
                            focus: entry.asked
                            clip: true
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12

                            Keys.onReturnPressed: parent.join()
                            Keys.onEnterPressed: parent.join()
                            Keys.onEscapePressed: page.asking = ""

                            Text {
                                textFormat: Text.PlainText
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
                            color: Theme.tint(Theme.accent, joinMouse.containsMouse ? 0.28 : 0.16)
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                id: joinText

                                textFormat: Text.PlainText
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

            Item {
                width: rows.width
                height: 12
            }
        }
    }
}

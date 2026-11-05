import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Security. Nothing runs in the background for this page: it asks
// scripts/yakushi-securityctl.py once when it opens (and once at login), and
// only what you press after that.
//
//   SHIELD    firewall, what listens to your network, SSH server, updates and
//             known security holes, auto lock, disk encryption, Secure Boot
//   GUARD     what changed in the places an intruder would use to stay
//   LOGINS    failed password attempts, sudo use, SSH logins
//   DEEP SCAN every system file compared with its package (on demand)
//
// Your password, when needed, is asked inside the page (PasswordRow) and goes
// to sudo through a pipe. UPDATE runs pacman -Syu right here with its progress;
// pacman runs on its own, so closing Settings never stops it halfway (opened
// again, the page picks the update up where it is).
Item {
    id: page

    property var hostWindow: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string helper: home + "/.config/quickshell/scripts/yakushi-securityctl.py"

    property var st: null                // the last `status`
    readonly property var fw: st ? st.firewall : null
    readonly property var upd: st ? st.updates : null
    readonly property var guard: st ? st.guard : null
    readonly property var events: guard && guard.events ? guard.events : ({})
    readonly property var scan: st ? st.scan : null
    readonly property var lock: st ? st.autolock : null

    // ---- one short line under the header
    property string note: ""
    property bool noteOk: true

    function say(text, ok) {
        note = text
        noteOk = ok !== false
    }

    // ---- reading
    function refresh() {
        statusProc.running = true
    }

    Component.onCompleted: {
        // the guard check is quick (a second): run it, then read the status
        guardProc.running = true
    }

    Process {
        id: guardProc
        command: ["python3", page.helper, "guard"]
        onExited: page.refresh()
    }

    Process {
        id: statusProc
        command: ["python3", page.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.ok) {
                        page.st = d
                        // an update started earlier still runs: show it again
                        if (d.upgrading && !upgrader.running)
                            page.followUpgrade()
                    }
                    else
                        page.say(d.message || "Could not read the status.", false)
                } catch (e) {
                    page.say("No answer from the helper.", false)
                }
            }
        }
    }

    // ---- doing
    readonly property bool busy: action.running || upgrader.running
    property string busyText: ""
    property var pendingArgs: []          // waiting for your password
    property string pendingLabel: ""
    property string pendingButton: ""
    property string secret: ""
    property var lastArgs: []
    property string armed: ""             // a risky button waiting for its second click

    Timer {
        id: disarm
        interval: 4000
        onTriggered: page.armed = ""
    }

    function confirm(key) {
        if (armed === key)
            return true
        armed = key
        disarm.restart()
        return false
    }

    function ask(args, label, button) {
        if (busy)
            return
        pendingArgs = args
        pendingLabel = label
        pendingButton = button
        passwordAsk.error = ""
        Qt.callLater(passwordAsk.open)
    }

    function run(args, pw, text) {
        if (action.running)
            return
        armed = ""
        busyText = text || "Working…"
        note = ""
        secret = pw
        lastArgs = args
        action.stdinEnabled = pw !== ""
        action.command = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : []).concat(args)
        action.running = true
    }

    Process {
        id: action

        onStarted: {
            if (stdinEnabled) {
                action.write(page.secret + "\n")
                page.secret = ""
                stdinEnabled = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                page.busyText = ""
                try {
                    var d = JSON.parse(text)
                    if (d.wrongPassword) {
                        page.pendingArgs = page.lastArgs
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    if (d.message)
                        page.say(d.message, d.ok !== false)
                } catch (e) {
                    page.say("No answer from the helper.", false)
                }
                page.refresh()
            }
        }
    }

    // ---- UPDATE, right here: pacman -Syu with its progress
    property var up: null                 // { phase, n, total, line } while it runs
    property var upLines: []              // the last few lines pacman wrote
    property var upResult: null           // { ok, message, terminal } when it ended
    property string upSecret: ""

    function startUpgrade(pw) {
        if (busy)
            return
        armed = ""
        note = ""
        upResult = null
        upLines = []
        up = { phase: "Starting", n: 0, total: 0, line: "" }
        upSecret = pw
        upgrader.stdinEnabled = true
        upgrader.command = ["python3", helper, "--password-stdin", "upgrade"]
        upgrader.running = true
    }

    function followUpgrade() {
        upResult = null
        upLines = []
        up = { phase: "Updating", n: 0, total: 0, line: "" }
        upgrader.stdinEnabled = false
        upgrader.command = ["python3", helper, "follow"]
        upgrader.running = true
    }

    Process {
        id: upgrader

        onStarted: {
            if (stdinEnabled) {
                upgrader.write(page.upSecret + "\n")
                page.upSecret = ""
                stdinEnabled = false
            }
        }

        stdout: SplitParser {
            onRead: function(data) {
                var d
                try {
                    d = JSON.parse(data)
                } catch (e) {
                    return
                }
                if (d.done) {
                    page.up = null
                    if (d.wrongPassword) {
                        page.upLines = []
                        page.ask(["upgrade"], "Your password, to update the system", "UPDATE")
                        passwordAsk.error = "Wrong password. Try again."
                        return
                    }
                    page.upResult = d
                    page.say(d.message || "", d.ok !== false)
                    page.refresh()
                    return
                }
                page.up = d
                if (d.line) {
                    var l = page.upLines.slice(-4)
                    l.push(d.line)
                    page.upLines = l
                }
            }
        }

        onExited: {
            if (page.up !== null) {          // it stopped without a last word
                page.up = null
                page.refresh()
            }
        }
    }

    // when pacman needs a decision from you: the same update in a terminal
    Process {
        id: terminal
        command: ["kitty", "--title", "Yakushi · system update", "sh", "-c",
                  "sudo pacman -Syu; echo; printf 'Done. Press Enter to close.'; read x"]
        onExited: page.run(["updates"], "", "Checking again for updates…")
    }

    // ---- words
    function ago(t) {
        if (!t)
            return "never"
        var s = Math.max(0, Math.floor(Date.now() / 1000) - t)
        if (s < 90)
            return "just now"
        if (s < 5400)
            return Math.round(s / 60) + " min ago"
        if (s < 129600)
            return Math.round(s / 3600) + " h ago"
        return Math.round(s / 86400) + " days ago"
    }

    function clock(t) {
        var d = new Date(t * 1000)
        return Qt.formatDateTime(d, "dd MMM hh:mm")
    }

    readonly property var holesFixed: upd && upd.holes ? upd.holes.filter(function(h) { return h.fix !== "" }) : []
    readonly property int pendingCount: upd && upd.pending ? upd.pending.length : 0
    readonly property var reachable: st ? st.listening : []

    // one line per program: "spotify   TCP 51885, 57621 · UDP 1900, 5353"
    readonly property var listeners: {
        var by = {}
        var order = []
        for (var i = 0; i < reachable.length; i++) {
            var r = reachable[i]
            var who = r.program !== "" ? r.program : "system services"
            if (!by[who]) {
                by[who] = { who: who, tcp: [], udp: [] }
                order.push(who)
            }
            var list = r.proto === "tcp" ? by[who].tcp : by[who].udp
            if (list.indexOf(r.port) < 0)
                list.push(r.port)
        }
        return order.map(function(w) { return by[w] })
    }

    // ------------------------------------------------------------------
    // Pieces
    // ------------------------------------------------------------------
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false
        property var host: null

        signal picked()

        width: chipText.implicitWidth + 22
        height: 28
        opacity: host && host.busy ? 0.5 : 1
        color: on ? Theme.tint(Theme.accent, 0.16)
            : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : "transparent"
        border.width: 1
        border.color: on ? Theme.accent : chipMouse.containsMouse ? Theme.lineHot : Theme.line

        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: !(chip.host && chip.host.busy)
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component Button: Rectangle {
        id: btn

        property string key: ""
        property string label: ""
        property bool danger: false
        property var host: null
        readonly property bool armedHere: host !== null && key !== "" && host.armed === key

        signal pressed()

        width: btnText.implicitWidth + 24
        height: 28
        opacity: host && host.busy ? 0.5 : 1
        color: armedHere ? Theme.tint(Theme.alert, 0.3)
            : danger ? (btnMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, btnMouse.containsMouse ? 0.26 : 0.12)
        border.width: 1
        border.color: danger || armedHere ? Theme.alert : Theme.tint(Theme.accent, 0.7)

        Text {
            id: btnText

            anchors.centerIn: parent
            text: btn.armedHere ? "CLICK AGAIN" : btn.label
            color: btn.danger || btn.armedHere ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: !(btn.host && btn.host.busy)
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.pressed()
        }
    }

    component Section: Item {
        property string label: ""
        property string side: ""

        width: parent ? parent.width : 0
        height: 34

        Text {
            id: secText

            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            text: parent.label
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }

        Text {
            anchors.right: parent.right
            anchors.baseline: secText.baseline
            text: parent.side
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.line
        }
    }

    // one line of the shield: a mark, a name, what it means, and its buttons
    component ShieldRow: Item {
        id: sr

        property string title: ""
        property string text: ""
        property string mood: "info"     // good | bad | info
        default property alias buttons: btnRow.data

        width: parent ? parent.width : 0
        height: Math.max(48, srText.implicitHeight + 24)

        Rectangle {
            id: mark

            x: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            color: sr.mood === "good" ? Theme.good : sr.mood === "bad" ? Theme.alert : Theme.inkMute
        }

        Text {
            id: srTitle

            anchors.left: mark.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 150
            text: sr.title
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 12
        }

        Text {
            id: srText

            anchors.left: srTitle.right
            anchors.leftMargin: 8
            anchors.right: btnRow.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: sr.text
            wrapMode: Text.WordWrap
            color: sr.mood === "bad" ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            lineHeight: 1.15
        }

        Row {
            id: btnRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.tint(Theme.ink, 0.04)
        }
    }

    // a small, dim line (a port, a CVE, a login try)
    component Detail: Text {
        property bool hot: false

        width: parent ? parent.width : 0
        leftPadding: 24
        elide: Text.ElideRight
        color: hot ? Theme.alert : Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 10
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    Item {
        id: head

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30

        PageTitle {
            anchors.left: parent.left
            anchors.right: headButtons.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "SECURITY"
        }

        Row {
            id: headButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Chip {
                host: page
                label: "CHECK NOW"
                onPicked: {
                    page.say("Checked: " + Qt.formatTime(new Date(), "hh:mm") + ".", true)
                    guardProc.running = true
                }
            }
        }
    }

    // the note, or the password row
    Item {
        id: bar

        anchors.top: head.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        PasswordRow {
            id: passwordAsk

            anchors.fill: parent
            visible: page.pendingArgs.length > 0
            label: page.pendingLabel
            action: page.pendingButton
            onAccepted: function(password) {
                var args = page.pendingArgs
                page.pendingArgs = []
                if (args[0] === "upgrade")
                    page.startUpgrade(password)
                else
                    page.run(args, password, page.busyFor(args))
            }
            onCanceled: {
                page.pendingArgs = []
                page.say("Cancelled. Nothing was changed.", true)
            }
        }

        Text {
            visible: !passwordAsk.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: page.up !== null ? "Updating the system: " + page.up.phase.toLowerCase()
                    + (page.up.total > 0 ? " (" + page.up.n + " of " + page.up.total + ")" : "") + "…"
                : page.busyText !== "" ? page.busyText
                : page.note !== "" ? page.note
                : page.st === null ? "Looking…"
                : "Nothing here runs in the background. The guard checks once at login and tells you only what is serious."
            color: page.busyText !== "" || page.up !== null ? Theme.accent : page.note !== "" && !page.noteOk ? Theme.alert
                : page.note !== "" ? Theme.ink : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 11
        }
    }

    function busyFor(args) {
        var k = args[0]
        return k === "scan" ? "Comparing every system file with its package… this takes a few minutes."
            : k === "firewall" ? (args[1] === "on" ? "Turning the firewall on…" : "Turning the firewall off…")
            : k === "ssh" ? "Turning the SSH server off…"
            : k === "autolock" ? "Setting auto lock…"
            : "Working…"
    }

    Flickable {
        id: scroll

        anchors.top: bar.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: body.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: scroll.width
            spacing: 0

            // ================= SHIELD =================
            Section {
                label: "SHIELD"
            }

            ShieldRow {
                title: "Firewall"
                mood: page.fw === null ? "info" : page.fw.on ? "good" : "bad"
                text: page.fw ? page.fw.text : "…"

                Button {
                    host: page
                    visible: page.fw !== null && !page.fw.on
                    label: "TURN ON"
                    onPressed: page.ask(["firewall", "on"], "Your password, to turn the firewall on", "TURN ON")
                }

                Button {
                    host: page
                    key: "fwoff"
                    visible: page.fw !== null && page.fw.on && page.fw.tool === "ufw"
                    label: "TURN OFF"
                    danger: true
                    onPressed: if (page.confirm("fwoff")) page.ask(["firewall", "off"], "Your password, to turn the firewall off", "TURN OFF")
                }
            }

            ShieldRow {
                title: "Open to network"
                mood: page.listeners.length === 0 || (page.fw && page.fw.on) ? "good" : "bad"
                text: page.st === null ? "…"
                    : page.listeners.length === 0 ? "Nothing on this computer listens to your network."
                    : page.listeners.length + (page.listeners.length === 1 ? " program listens" : " programs listen")
                      + " to your network." + (page.fw && page.fw.on
                          ? " The firewall keeps them closed unless you allowed them."
                          : " Without a firewall, anyone on your network can try them.")
            }

            Column {
                width: parent.width
                visible: page.listeners.length > 0
                topPadding: 2
                bottomPadding: 8
                spacing: 3

                Repeater {
                    model: page.listeners

                    Detail {
                        required property var modelData

                        text: modelData.who + "   "
                            + [modelData.tcp.length ? "TCP " + modelData.tcp.join(", ") : "",
                               modelData.udp.length ? "UDP " + modelData.udp.join(", ") : ""]
                              .filter(function(x) { return x !== "" }).join("  ·  ")
                    }
                }
            }

            ShieldRow {
                title: "SSH server"
                mood: page.st === null ? "info" : page.st.ssh.active || page.st.ssh.enabled ? "bad" : "good"
                text: page.st === null ? "…"
                    : page.st.ssh.active ? "On: others can try to log in to this computer over the network."
                    : page.st.ssh.enabled ? "Off now, but it starts at boot."
                    : "Off: nobody can log in to this computer over the network."

                Button {
                    host: page
                    visible: page.st !== null && (page.st.ssh.active || page.st.ssh.enabled)
                    label: "TURN OFF"
                    danger: true
                    onPressed: page.ask(["ssh", "off"], "Your password, to turn the SSH server off", "TURN OFF")
                }
            }

            ShieldRow {
                title: "Updates"
                mood: page.upd === null ? "info" : page.holesFixed.length > 0 ? "bad" : page.pendingCount > 0 ? "info" : "good"
                text: page.upd === null ? "Not checked yet. CHECK asks the Arch mirrors and the Arch security tracker."
                    : (page.pendingCount === 0 ? "Everything is up to date."
                       : page.pendingCount + (page.pendingCount === 1 ? " update waits" : " updates wait")
                         + (page.holesFixed.length > 0 ? ", " + page.holesFixed.length
                            + (page.holesFixed.length === 1 ? " of them fixes" : " of them fix") + " a known security hole." : "."))
                      + "  Checked " + page.ago(page.upd.time) + "."
                      + (page.upd.errors && page.upd.errors.length ? "  (" + page.upd.errors[0] + ")" : "")

                Button {
                    host: page
                    label: "CHECK"
                    onPressed: page.run(["updates"], "", "Asking the mirrors and the security tracker…")
                }

                Button {
                    host: page
                    visible: page.pendingCount > 0 && page.up === null
                    label: "UPDATE"
                    onPressed: page.ask(["upgrade"], "Your password, to update the system", "UPDATE")
                }

                Button {
                    host: page
                    visible: page.up === null && page.upResult !== null && page.upResult.terminal === true
                    label: "OPEN IN TERMINAL"
                    onPressed: terminal.running = true
                }
            }

            // the update, while it runs (and what went wrong, if it did)
            Item {
                id: upPanel

                readonly property bool running: page.up !== null
                readonly property bool failed: !running && page.upResult !== null && page.upResult.ok === false

                width: parent.width
                visible: running || failed
                height: visible ? upCol.implicitHeight + 18 : 0

                Column {
                    id: upCol

                    x: 24
                    y: 6
                    width: parent.width - 24
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 16
                        visible: upPanel.running

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.up ? page.up.phase.toUpperCase() : ""
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.up && page.up.total > 0 ? page.up.n + " / " + page.up.total : ""
                            color: Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }
                    }

                    // the bar: steps when pacman counts them, a moving block when it does not
                    Rectangle {
                        id: track

                        visible: upPanel.running
                        width: parent.width
                        height: 4
                        color: Theme.groove
                        clip: true

                        readonly property bool counted: page.up !== null && page.up.total > 0

                        Rectangle {
                            visible: track.counted
                            width: track.counted ? track.width * Math.min(1, page.up.n / page.up.total) : 0
                            height: parent.height
                            color: Theme.accent

                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }

                        Rectangle {
                            id: sweep

                            visible: !track.counted
                            width: track.width * 0.22
                            height: parent.height
                            color: Theme.accent

                            NumberAnimation on x {
                                running: upPanel.running && !track.counted && page.visible
                                from: -sweep.width
                                to: track.width
                                duration: 1300
                                loops: Animation.Infinite
                            }
                        }
                    }

                    Repeater {
                        model: page.upLines

                        Detail {
                            required property var modelData

                            leftPadding: 0
                            hot: /^error/.test(modelData)
                            text: modelData
                        }
                    }

                    Text {
                        visible: upPanel.running
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "You can close Settings: the update goes on, and this page shows it again when you come back."
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }
                }
            }

            Column {
                width: parent.width
                visible: page.upd !== null && page.upd.holes && page.upd.holes.length > 0
                topPadding: 2
                bottomPadding: 8
                spacing: 3

                Repeater {
                    model: page.upd && page.upd.holes ? page.upd.holes : []

                    Detail {
                        required property var modelData

                        hot: modelData.fix !== "" && (modelData.risk === "high" || modelData.risk === "critical")
                        text: modelData.name + "   " + modelData.risk + " risk   " + modelData.issues.join(", ")
                            + (modelData.count > modelData.issues.length ? " +" + (modelData.count - modelData.issues.length) : "")
                            + (modelData.fix !== "" ? "   fixed in " + modelData.fix : "   no fix yet")
                    }
                }
            }

            ShieldRow {
                title: "Auto lock"
                mood: page.lock === null ? "info" : page.lock.minutes === "off" ? "bad" : "good"
                text: page.lock === null ? "…"
                    : page.lock.minutes === "off" ? "Off: the screen stays open when you walk away."
                    : "Locks after " + page.lock.minutes + " idle minutes, and before sleep."

                Repeater {
                    model: [["off", "OFF"], ["5", "5"], ["10", "10"], ["15", "15"], ["30", "30 MIN"]]

                    Chip {
                        required property var modelData

                        host: page
                        label: modelData[1]
                        on: page.lock !== null && page.lock.minutes === modelData[0]
                        onPicked: {
                            if (on)
                                return
                            if (modelData[0] !== "off" && !(page.st && page.st.tools.hypridle))
                                page.ask(["autolock", modelData[0]], "Your password, to install hypridle (official repository)", "INSTALL")
                            else
                                page.run(["autolock", modelData[0]], "", "Setting auto lock…")
                        }
                    }
                }
            }

            ShieldRow {
                title: "Disk encryption"
                mood: page.st === null || !page.st.encryption.known ? "info" : page.st.encryption.on ? "good" : "info"
                text: page.st === null ? "…"
                    : !page.st.encryption.known ? "Could not tell how your system disk is set up."
                    : page.st.encryption.on ? "On: without your passphrase the disk cannot be read, even if it is taken out."
                    : "Off: someone holding the disk could read it. Encryption is chosen when installing; it cannot be turned on safely from here."
            }

            ShieldRow {
                title: "Secure Boot"
                mood: page.st === null || !page.st.secureBoot.known ? "info" : page.st.secureBoot.on ? "good" : "info"
                text: page.st === null ? "…"
                    : !page.st.secureBoot.efi ? "This computer starts in legacy (BIOS) mode, without Secure Boot."
                    : !page.st.secureBoot.known ? "Could not read the Secure Boot setting."
                    : page.st.secureBoot.on ? "On: the firmware only starts signed boot files."
                    : "Off. It is a firmware (BIOS) setting and needs signed boot files; leave it unless you plan for it."
            }

            // ================= GUARD =================
            Section {
                label: "GUARD"
                side: page.guard && page.guard.time ? "checked " + page.ago(page.guard.time) : ""
            }

            Item {
                width: parent.width
                height: guardText.implicitHeight + 20

                Text {
                    id: guardText

                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.right: guardButtons.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    text: page.guard === null ? "…"
                        : page.guard.changes.length === 0
                          ? "Nothing changed. Watching what starts at login, services and timers, users and the wheel group, SSH keys, shell start files, /etc/ld.so.preload, pacman.conf and what listens to your network."
                          : page.guard.changes.length + (page.guard.changes.length === 1 ? " change" : " changes")
                            + " since you last accepted. If you did it (installed something, edited a file), press THAT WAS ME. If not, look closer before anything else."
                    color: page.guard && page.guard.changes.length > 0 ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    lineHeight: 1.15
                }

                Row {
                    id: guardButtons

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                        host: page
                        visible: page.guard !== null && page.guard.changes.length > 1
                        label: "ALL WERE ME"
                        onPressed: page.run(["accept", "all"], "", "Taking them as yours…")
                    }
                }
            }

            Repeater {
                model: page.guard ? page.guard.changes : []

                Item {
                    id: change

                    required property var modelData

                    width: body.width
                    height: 34

                    Rectangle {
                        x: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        color: change.modelData.kind === "gone" ? Theme.inkMute : Theme.alert
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 24
                        anchors.right: meButton.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: change.modelData.text
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }

                    Button {
                        id: meButton

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        host: page
                        label: "THAT WAS ME"
                        onPressed: page.run(["accept", change.modelData.key], "", "Taking it as yours…")
                    }
                }
            }

            // ================= LOGINS =================
            Section {
                label: "PASSWORDS AND LOGINS"
                side: page.events.since ? "since " + page.clock(page.events.since) : ""
            }

            Item {
                width: parent.width
                height: loginText.implicitHeight + 20

                Text {
                    id: loginText

                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.right: seenButton.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    readonly property var f: page.events.failed || []
                    readonly property var s: page.events.sudo || []
                    readonly property var r: page.events.ssh || []
                    text: page.events.readable === false
                          ? "Your user cannot read the system journal. Being in the wheel group allows it."
                          : (f.length === 0 ? "No wrong passwords." : f.length + (f.length === 1 ? " wrong password." : " wrong passwords."))
                            + "  " + (s.length === 0 ? "sudo was not used." : "sudo used " + s.length + (s.length === 1 ? " time." : " times."))
                            + (r.length > 0 ? "  " + r.length + " SSH login" + (r.length === 1 ? "." : "s.") : "")
                    color: f.length > 0 || r.length > 0 ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    lineHeight: 1.15
                }

                Button {
                    id: seenButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    host: page
                    visible: (page.events.failed || []).length + (page.events.sudo || []).length + (page.events.ssh || []).length > 0
                    label: "SEEN"
                    onPressed: page.run(["seen"], "", "Clearing the list…")
                }
            }

            Column {
                width: parent.width
                bottomPadding: 8
                spacing: 3

                Repeater {
                    model: (page.events.failed || []).slice(-8).reverse()

                    Detail {
                        required property var modelData

                        hot: true
                        text: page.clock(modelData.time) + "   " + (modelData.remote ? "from the network (SSH)   " : "")
                            + modelData.text
                    }
                }

                Repeater {
                    model: (page.events.ssh || []).slice(-5).reverse()

                    Detail {
                        required property var modelData

                        hot: true
                        text: page.clock(modelData.time) + "   SSH   " + modelData.text
                    }
                }

                Repeater {
                    model: (page.events.sudo || []).slice(-8).reverse()

                    Detail {
                        required property var modelData

                        text: page.clock(modelData.time) + "   sudo   " + modelData.text
                    }
                }
            }

            // ================= DEEP SCAN =================
            Section {
                label: "DEEP SCAN"
                side: page.scan ? "last " + page.ago(page.scan.time) : ""
            }

            Item {
                width: parent.width
                height: scanText.implicitHeight + 20

                Text {
                    id: scanText

                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.right: scanButton.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    text: page.scan === null
                          ? "Compares every program and library with the copy its package installed, to find anything swapped or patched. Takes a few minutes; nothing is changed."
                          : page.scan.redCount === 0
                            ? "Every system program and library matches its package. " + page.scan.configs
                              + " settings files in /etc differ from their defaults, which is normal."
                            : page.scan.redCount + " system files differ from their package. A broken update can do this too: "
                              + "reinstalling the package (sudo pacman -S <name>) puts the right copy back."
                    color: page.scan && page.scan.redCount > 0 ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    lineHeight: 1.15
                }

                Button {
                    id: scanButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    host: page
                    label: page.scan ? "SCAN AGAIN" : "SCAN"
                    onPressed: page.ask(["scan"], "Your password, to read every system file", "SCAN")
                }
            }

            Column {
                width: parent.width
                visible: page.scan !== null && page.scan.redCount > 0
                bottomPadding: 8
                spacing: 3

                Repeater {
                    model: page.scan && page.scan.red ? page.scan.red.slice(0, 20) : []

                    Detail {
                        required property var modelData

                        hot: true
                        text: modelData.path + "   " + modelData.package + "   " + modelData.why.toLowerCase()
                    }
                }
            }
        }
    }
}

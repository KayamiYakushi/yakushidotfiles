import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Tasks: what runs on this computer, and why.
// scripts/yakushi-taskctl.py streams CPU, memory and every process every
// 1.5 s while this page is open (it stops with the page). Processes in
// trouble get a tag (NOT RESPONDING, STUCK, PAUSED, ...) and apps that stopped
// answering are named in a banner on top. Pick a process to see, in plain
// words, which package it comes from, why that package is installed and who
// started it, and to end it (END asks it to quit, FORCE END stops it at once).
// REMOVE PACKAGE (or REMOVE A PACKAGE on top) opens RemovePanel: what goes,
// with a preview, one password prompt and UNDO. SUPER + Esc opens it here.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-taskctl.py"

    // ---- live data
    property real cpu: -1
    property real memUsed: 0
    property real memTotal: 0
    property int total: 0
    property int withWindows: 0
    property var procs: []
    property var trouble: []           // apps not responding / stuck: shown in the banner
    property bool removing: false      // the remove-a-package panel is open
    property bool showWhy: false       // the WHY IT RUNS tick: explanations under the picked process

    // ---- what you look at
    property string scope: "mine"      // apps | mine | all
    property string sortBy: "cpu"      // cpu | mem | name
    property string search: ""
    property int selected: -1          // pid
    property var order: []             // pids in the order shown (kept while the pointer is on the list)

    Process {
        id: stream

        command: ["python3", page.helper, "stream"]
        running: true

        stdout: SplitParser {
            onRead: data => page.take(data)
        }
    }

    function take(line) {
        var d
        try {
            d = JSON.parse(line)
        } catch (e) {
            return
        }
        cpu = d.cpu
        memUsed = d.memUsed
        memTotal = d.memTotal
        total = d.procs.length
        var w = 0
        for (var i = 0; i < d.procs.length; i++)
            if (d.procs[i].window !== "")
                w++
        withWindows = w
        procs = d.procs
        var bad = []
        for (var j = 0; j < d.procs.length; j++)
            if (d.procs[j].flag === "anr" || (d.procs[j].flag === "stuck" && d.procs[j].mine))
                bad.push(d.procs[j])
        if (JSON.stringify(bad.map(function(p) { return p.pid + p.flag })) !== JSON.stringify(trouble.map(function(p) { return p.pid + p.flag })))
            trouble = bad
        refresh()
    }

    function visibleProcs() {
        var q = search.trim().toLowerCase()
        return procs.filter(function(p) {
            if (scope === "apps" && p.window === "")
                return false
            if (scope === "mine" && !p.mine)
                return false
            if (q === "")
                return true
            return (p.name + " " + p.proc + " " + p.cmd + " " + p.pid + " " + p.window).toLowerCase().indexOf(q) >= 0
        })
    }

    function sorted(list) {
        var key = sortBy
        return list.sort(function(a, b) {
            if (key === "name")
                return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : a.pid - b.pid
            var x = key === "mem" ? b.mem - a.mem : b.cpu - a.cpu
            return x !== 0 ? x : (key === "cpu" ? b.mem - a.mem : a.pid - b.pid)
        })
    }

    // rows keep their place while the pointer is over the list, so what
    // you are about to click does not run away
    function refresh() {
        var list = visibleProcs()
        if (listHover.hovered && order.length > 0) {
            var byPid = {}
            for (var i = 0; i < list.length; i++)
                byPid[list[i].pid] = list[i]
            var kept = []
            for (var j = 0; j < order.length; j++)
                if (byPid[order[j]] !== undefined) {
                    kept.push(byPid[order[j]])
                    delete byPid[order[j]]
                }
            for (var pid in byPid)
                kept.push(byPid[pid])
            list = kept
        } else {
            list = sorted(list)
        }
        order = list.map(function(p) { return p.pid })
        // same rows, new values: the view is not rebuilt
        for (var k = 0; k < list.length; k++) {
            var p = list[k]
            var row = { pid: p.pid, name: p.name, proc: p.proc, user: p.user, cpu: p.cpu, mem: p.mem,
                        state: p.state, window: p.window, mine: p.mine, flag: p.flag || "" }
            if (k < rows.count)
                rows.set(k, row)
            else
                rows.append(row)
        }
        if (rows.count > list.length)
            rows.remove(list.length, rows.count - list.length)
    }

    onScopeChanged: refresh()
    onSortByChanged: refresh()
    onSearchChanged: refresh()

    ListModel {
        id: rows
    }

    // ---- details of the picked process
    property var info: null
    property bool asking: why.running

    function pick(pid) {
        if (selected === pid) {
            selected = -1
            info = null
            return
        }
        inspect(pid)
    }

    function inspect(pid) {
        selected = pid
        info = null
        armed = ""
        pendingAct = ""
        actionNote = ""
        why.command = ["python3", helper, "why", String(pid)]
        why.running = true
    }

    // ---- ending: END / FORCE END / CONTINUE / STOP SERVICE
    property string armed: ""          // the action waiting for its second click
    property string actionNote: ""
    property bool actionOk: true
    readonly property bool acting: action.running

    function act(kind) {
        if (!info || !info.facts || acting)
            return
        if (kind === "remove") {
            if (info.package) {
                removing = true
                remover.openPlan([info.package.name])
            }
            return
        }
        var risky = kind === "force" || kind === "stop" || (info.guard && info.guard.level !== "")
        if (risky && armed !== kind) {
            armed = kind
            disarm.restart()
            return
        }
        armed = ""
        // other users' processes and system services need your password:
        // it is asked right here (no dialog that would open behind Settings)
        if (info.other || (kind === "stop" && info.unit && !info.unit.user)) {
            pendingAct = kind
            actionNote = ""
            passwordAsk.error = ""
            Qt.callLater(passwordAsk.open)
            return
        }
        run(kind, "")
    }

    property string pendingAct: ""     // the action waiting for your password
    property string secret: ""

    function run(kind, pw) {
        var f = info.facts
        actionNote = kind === "end" ? "Asking it to quit…" : kind === "force" ? "Stopping it…"
            : kind === "cont" ? "Letting it go on…" : "Stopping the service…"
        actionOk = true
        secret = pw
        action.stdinEnabled = pw !== ""
        lastKind = kind
        var head = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : [])
        action.command = kind === "stop"
            ? head.concat(["stop-unit", info.unit.name, info.unit.user ? "user" : "system"])
            : head.concat([kind, String(f.pid), String(f.start)])
        action.running = true
    }

    property string lastKind: ""

    Timer {
        id: disarm
        interval: 4000
        onTriggered: page.armed = ""
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
                try {
                    var d = JSON.parse(text)
                    if (d.wrongPassword) {
                        page.pendingAct = page.lastKind
                        page.actionNote = ""
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    page.actionNote = d.message || ""
                    page.actionOk = d.ok !== false
                } catch (e) {
                    page.actionNote = "No answer from the helper."
                    page.actionOk = false
                }
            }
        }
    }

    Process {
        id: why

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.info = JSON.parse(text)
                } catch (e) {
                    page.info = { ok: false, message: "No answer from the helper." }
                }
            }
        }
    }

    readonly property bool selectedAlive: procs.some(function(p) { return p.pid === page.selected && p.state !== "Z" })

    function flagText(flag) {
        return flag === "anr" ? "NOT RESPONDING" : flag === "stuck" ? "STUCK" : flag === "stopped" ? "PAUSED"
            : flag === "zombie" ? "ENDED" : flag === "busy" ? "BUSY" : ""
    }

    function flagHint(flag) {
        return flag === "anr" ? "Its window stopped answering Hyprland. END may not work; FORCE END will."
            : flag === "stuck" ? "It has been waiting on a disk or a driver for a while."
            : flag === "stopped" ? "Paused (stopped). CONTINUE lets it go on."
            : flag === "zombie" ? "It has ended; its parent has not collected it yet."
            : flag === "busy" ? "Using a whole CPU core for a while. Often fine (a game, a build)."
            : ""
    }

    readonly property string selectedFlag: {
        for (var i = 0; i < procs.length; i++)
            if (procs[i].pid === selected)
                return procs[i].flag || ""
        return ""
    }

    // ---- formatting
    function bytes(n) {
        if (n >= 1073741824)
            return (n / 1073741824).toFixed(n >= 10737418240 ? 0 : 1) + " GB"
        if (n >= 1048576)
            return Math.round(n / 1048576) + " MB"
        return Math.round(n / 1024) + " KB"
    }

    function stateText(s) {
        return s === "R" ? "running" : s === "S" ? "sleeping" : s === "D" ? "waiting on disk"
            : s === "T" || s === "t" ? "stopped" : s === "Z" ? "zombie (ended, not collected)" : s === "I" ? "idle" : s
    }

    function kindGlyph(kind) {
        return kind === "package" ? String.fromCodePoint(0xF03D7)
            : kind === "reason" ? String.fromCodePoint(0xF02FD)
            : kind === "start" ? String.fromCodePoint(0xF040A)
            : kind === "window" ? String.fromCodePoint(0xF05AF)
            : kind === "kernel" || kind === "core" ? String.fromCodePoint(0xF033D)
            : kind === "yakushi" ? "薬"
            : String.fromCodePoint(0xF0214)
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false

        signal picked()

        width: chipText.implicitWidth + 24
        height: 30
        color: on ? Theme.tint(Theme.accent, 0.16)
            : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : "transparent"
        border.width: 1
        border.color: on ? Theme.accent : chipMouse.containsMouse ? Theme.lineHot : Theme.line

        Text {
            id: chipText

            textFormat: Text.PlainText
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
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component ActButton: Rectangle {
        id: act

        property string key: ""
        property string label: ""
        property bool danger: false
        property var host: null              // the page: inline components do not see its id
        readonly property bool armedHere: host !== null && host.armed === key

        width: actText.implicitWidth + 26
        height: 32
        opacity: host && host.acting ? 0.5 : 1
        color: armedHere ? Theme.tint(Theme.alert, 0.3)
            : danger ? (actMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, actMouse.containsMouse ? 0.26 : 0.12)
        border.width: 1
        border.color: danger || armedHere ? Theme.alert : Theme.tint(Theme.accent, 0.7)

        Text {
            id: actText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: act.armedHere ? "CLICK AGAIN" : act.label
            color: act.danger || act.armedHere ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: actMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: host !== null && !host.acting
            cursorShape: Qt.PointingHandCursor
            onClicked: act.host.act(act.key)
        }
    }

    component Meter: Item {
        property string label: ""
        property string value: ""
        property real fraction: 0
        property bool bar: true

        height: 42

        Text {
            id: meterLabel

            textFormat: Text.PlainText
            text: parent.label
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.baseline: meterLabel.baseline
            text: parent.value
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 14
        }

        Rectangle {
            visible: parent.bar
            anchors.bottom: parent.bottom
            width: parent.width
            height: 5
            color: Theme.groove

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, parent.parent.fraction))
                height: parent.height
                radius: parent.radius
                color: parent.parent.fraction > 0.9 ? Theme.alert : Theme.accent

                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
            }
        }
    }

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
            title: "TASKS"
        }

        // remove a package (also from a process: REMOVE PACKAGE below)
        Row {
            id: headButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Chip {
                label: "REMOVE A PACKAGE"
                on: page.removing && remover.view !== "removed"
                onPicked: {
                    page.removing = true
                    remover.openSearch("")
                }
            }

            Chip {
                label: "REMOVED BEFORE" + (remover.history.length ? "  " + remover.history.length : "")
                on: page.removing && remover.view === "removed"
                onPicked: {
                    page.removing = true
                    remover.openRemoved()
                }
            }
        }
    }

    Rectangle {
        id: rule

        anchors.top: head.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    // ---- CPU, memory, how many
    Row {
        id: meters

        anchors.top: rule.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 20

        readonly property real cell: (width - spacing * 2) / 3

        Meter {
            width: meters.cell
            label: "CPU"
            value: page.cpu < 0 ? "…" : Math.round(page.cpu) + "%"
            fraction: page.cpu / 100
        }

        Meter {
            width: meters.cell
            label: "MEMORY"
            value: page.memTotal ? page.bytes(page.memUsed) + " / " + page.bytes(page.memTotal) : "…"
            fraction: page.memTotal ? page.memUsed / page.memTotal : 0
        }

        Meter {
            width: meters.cell
            label: "PROCESSES"
            value: page.total ? page.total + "  ·  " + page.withWindows + " apps" : "…"
            bar: false
        }
    }

    // ---- apps that stopped answering
    Rectangle {
        id: banner

        visible: page.trouble.length > 0
        anchors.top: meters.bottom
        anchors.topMargin: visible ? 16 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 : 0
        color: Theme.tint(Theme.alert, 0.12)
        border.width: 1
        border.color: Theme.tint(Theme.alert, 0.6)

        Text {
            id: bannerGlyph

            textFormat: Text.PlainText
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0026)
            color: Theme.alert
            font.family: Theme.glyphs
            font.pixelSize: 16
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: bannerGlyph.right
            anchors.leftMargin: 10
            anchors.right: bannerButtons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
                var t = page.trouble
                if (t.length === 0)
                    return ""
                var first = t[0]
                var what = first.flag === "anr" ? " is not responding." : " is stuck."
                return first.name + what + (t.length > 1 ? "  (+" + (t.length - 1) + " more)" : "")
            }
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 12
        }

        Row {
            id: bannerButtons

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: page.trouble.slice(0, 3)

                delegate: Rectangle {
                    required property var modelData

                    width: showText.implicitWidth + 22
                    height: 30
                    color: showMouse.containsMouse ? Theme.tint(Theme.alert, 0.24) : "transparent"
                    border.width: 1
                    border.color: Theme.tint(Theme.alert, 0.7)

                    Text {
                        id: showText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: page.trouble.length > 1 ? "SHOW " + parent.modelData.name.toUpperCase().slice(0, 14) : "SHOW"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        id: showMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.inspect(parent.modelData.pid)
                    }
                }
            }
        }
    }

    // ---- which, in which order, search
    Item {
        id: tools

        anchors.top: banner.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34

        Row {
            id: showChips

            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Chip { label: "APPS"; on: page.scope === "apps"; onPicked: page.scope = "apps" }
            Chip { label: "MINE"; on: page.scope === "mine"; onPicked: page.scope = "mine" }
            Chip { label: "ALL"; on: page.scope === "all"; onPicked: page.scope = "all" }
        }

        Rectangle {
            id: searchBox

            anchors.left: showChips.right
            anchors.leftMargin: 12
            anchors.right: sortChips.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            color: Theme.tint(Theme.ink, 0.03)
            border.width: 1
            border.color: searchInput.activeFocus ? Theme.accent : Theme.line

            Text {
                id: lens

                textFormat: Text.PlainText
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0349)
                color: Theme.inkMute
                font.family: Theme.glyphs
                font.pixelSize: 12
            }

            TextInput {
                id: searchInput

                anchors.left: lens.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Theme.ink
                selectByMouse: true
                font.family: Theme.mono
                font.pixelSize: 12
                onTextChanged: page.search = text
                // Esc clears the search; on an empty one it closes Settings
                Keys.onEscapePressed: event => {
                    if (text !== "")
                        text = ""
                    else
                        event.accepted = false
                }

                Text {
                    textFormat: Text.PlainText
                    visible: searchInput.text === "" && !searchInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search name, command or PID"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
        }

        Row {
            id: sortChips

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Chip { label: "CPU"; on: page.sortBy === "cpu"; onPicked: page.sortBy = "cpu" }
            Chip { label: "MEMORY"; on: page.sortBy === "mem"; onPicked: page.sortBy = "mem" }
            Chip { label: "NAME"; on: page.sortBy === "name"; onPicked: page.sortBy = "name" }
        }
    }

    // ---- column titles
    Item {
        id: columns

        anchors.top: tools.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        height: 18

        Text {
            textFormat: Text.PlainText
            x: 16
            text: "NAME"
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: 16 + 96 + 20
            width: 64
            horizontalAlignment: Text.AlignRight
            text: "CPU"
            color: page.sortBy === "cpu" ? Theme.accent : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: 16
            width: 96
            horizontalAlignment: Text.AlignRight
            text: "MEMORY"
            color: page.sortBy === "mem" ? Theme.accent : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }
    }

    // ---- the list
    ListView {
        id: list

        anchors.top: columns.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: detail.visible ? detail.top : parent.bottom
        anchors.bottomMargin: detail.visible ? 10 : 0
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: rows
        reuseItems: true

        HoverHandler {
            id: listHover
        }

        delegate: Rectangle {
            id: line

            required property int pid
            required property string name
            required property string proc
            required property string user
            required property real cpu
            required property real mem
            required property string state
            required property string window
            required property bool mine
            required property string flag

            readonly property bool picked: page.selected === pid

            width: list.width
            height: 50
            color: picked ? Theme.tint(Theme.accent, 0.14)
                : lineMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : Theme.card
            border.width: 1
            border.color: picked ? Theme.accent : Theme.line

            // state: a dot (running = accent, stuck on disk / stopped = alert)
            Rectangle {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: line.state === "R" ? Theme.accent
                    : line.state === "D" || line.state === "T" || line.state === "Z" ? Theme.alert
                    : Theme.lineHot
            }

            Text {
                id: lineName

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: tag.visible ? tag.left : cpuText.left
                anchors.rightMargin: 16
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                elide: Text.ElideRight
                text: line.name
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 13
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: lineName.left
                anchors.right: lineName.right
                anchors.top: parent.verticalCenter
                anchors.topMargin: 4
                elide: Text.ElideRight
                text: (line.window !== "" ? "▣ " + line.window + "  ·  " : "") + line.proc + "  ·  " + line.pid
                    + (line.mine ? "" : "  ·  " + line.user)
                color: line.window !== "" ? Theme.inkSoft : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
            }

            // NOT RESPONDING / STUCK / PAUSED / ENDED / BUSY
            Rectangle {
                id: tag

                visible: line.flag !== ""
                anchors.right: cpuText.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: tagText.implicitWidth + 16
                height: 22
                readonly property bool bad: line.flag === "anr" || line.flag === "stuck"
                color: bad ? Theme.tint(Theme.alert, 0.18) : Theme.tint(Theme.ink, 0.06)
                border.width: 1
                border.color: bad ? Theme.alert : Theme.lineHot

                Text {
                    id: tagText

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: page.flagText(line.flag)
                    color: tag.bad ? Theme.alert : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            Text {
                id: cpuText

                textFormat: Text.PlainText
                anchors.right: memText.left
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                horizontalAlignment: Text.AlignRight
                text: line.cpu >= 10 ? Math.round(line.cpu) + "%" : line.cpu.toFixed(1) + "%"
                color: line.cpu >= 50 ? Theme.alert : line.cpu >= 1 ? Theme.ink : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 12
            }

            Text {
                id: memText

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                horizontalAlignment: Text.AlignRight
                text: page.bytes(line.mem)
                color: line.mem >= 1073741824 ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }

            MouseArea {
                id: lineMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.pick(line.pid)
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: rows.count === 0
            anchors.centerIn: parent
            text: page.cpu < 0 ? "Reading…" : page.search !== "" ? "Nothing matches “" + page.search + "”." : "Nothing here."
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
        }
    }

    ScrollHint {
        flick: list
        opacity: page.removing ? 0 : 1
    }

    // ---- why it runs
    Rectangle {
        id: detail

        visible: page.selected >= 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // compact: name, facts and the buttons; tick WHY IT RUNS for the rest
        height: Math.min(parent.height * (page.showWhy ? 0.5 : 0.45), detailBody.implicitHeight + 40 + actions.height)

        Behavior on height {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }
        color: Theme.card
        border.width: 1
        border.color: Theme.tint(Theme.accent, 0.5)

        readonly property var facts: page.info && page.info.facts ? page.info.facts : null

        // close
        Rectangle {
            id: closeButton

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            width: 30
            height: 30
            color: closeMouse.containsMouse ? Theme.tint(Theme.ink, 0.08) : "transparent"
            border.width: 1
            border.color: Theme.line
            z: 2

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "✕"
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.pick(page.selected)
            }
        }

        // ---- END / FORCE END / CONTINUE / STOP SERVICE
        Item {
            id: actions

            readonly property var guard: page.info && page.info.guard ? page.info.guard : null
            readonly property bool canEnd: detail.facts !== null && page.selectedAlive
                && actions.guard !== null && actions.guard.level !== "none"

            visible: detail.facts !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: visible ? 62 : 0

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            PasswordRow {
                id: passwordAsk

                visible: page.pendingAct !== ""
                z: 3
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                label: "Your password, to " + (page.pendingAct === "stop" ? "stop the service" : page.pendingAct === "cont" ? "let it go on" : "end it")
                action: page.pendingAct === "force" ? "FORCE END" : page.pendingAct === "stop" ? "STOP" : page.pendingAct === "cont" ? "CONTINUE" : "END"
                onAccepted: password => {
                    var kind = page.pendingAct
                    page.pendingAct = ""
                    page.run(kind, password)
                }
                onCanceled: {
                    page.pendingAct = ""
                    page.actionNote = "Cancelled. Nothing was changed."
                    page.actionOk = true
                }
            }

            // the tick: explanations on / off
            Item {
                id: whyToggle

                visible: page.pendingAct === ""
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: whyBox.width + 10 + whyLabel.implicitWidth
                height: 30

                Rectangle {
                    id: whyBox

                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    color: page.showWhy ? Theme.accent : "transparent"
                    border.width: 1
                    border.color: page.showWhy || whyMouse.containsMouse ? Theme.accent : Theme.lineHot

                    Text {
                        textFormat: Text.PlainText
                        visible: page.showWhy
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.surface
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Text {
                    id: whyLabel

                    textFormat: Text.PlainText
                    anchors.left: whyBox.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WHY IT RUNS"
                    color: page.showWhy || whyMouse.containsMouse ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                MouseArea {
                    id: whyMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.showWhy = !page.showWhy
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: page.pendingAct === ""
                anchors.left: whyToggle.right
                anchors.leftMargin: 20
                anchors.right: buttons.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: page.actionNote !== "" ? page.actionNote
                    : page.armed !== "" ? (page.armed === "force" ? "FORCE END stops it at once: unsaved work in it is lost. Click again to do it."
                                          : page.armed === "stop" ? "The service stops (it may start again later). Click again to do it."
                                          : "Click again to do it.")
                    : actions.guard && actions.guard.text !== "" ? actions.guard.text
                    : page.info && page.info.other ? "It belongs to another user: ending it asks for your password."
                    : !page.selectedAlive && detail.facts ? "It has ended."
                    : ""
                color: page.actionNote !== "" ? (page.actionOk ? Theme.ink : Theme.alert)
                    : page.armed !== "" || (actions.guard && actions.guard.level !== "") ? Theme.alert : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Row {
                id: buttons

                visible: page.pendingAct === ""
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ActButton {
                    key: "cont"
                    host: page
                    label: "CONTINUE"
                    visible: actions.canEnd && page.selectedFlag === "stopped"
                }

                ActButton {
                    key: "stop"
                    host: page
                    label: "STOP SERVICE"
                    visible: actions.canEnd && page.info.unit !== null && page.info.unit !== undefined
                }

                ActButton {
                    key: "remove"
                    host: page
                    label: "REMOVE PACKAGE"
                    danger: true
                    visible: detail.facts !== null && page.info.package !== null && page.info.package !== undefined
                }

                ActButton {
                    key: "end"
                    host: page
                    label: "END"
                    visible: actions.canEnd
                }

                ActButton {
                    key: "force"
                    host: page
                    label: "FORCE END"
                    danger: true
                    visible: actions.canEnd
                }
            }
        }

        Flickable {
            id: detailScroll

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: actions.top
            anchors.margins: 20
            anchors.rightMargin: 52
            anchors.bottomMargin: 8
            contentHeight: detailBody.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: detailBody

                width: detailScroll.width
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    visible: page.info === null || page.info.ok === false
                    text: page.info === null ? "Looking it up…" : page.info.message || "Could not look it up."
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                // name and the short facts
                Column {
                    visible: detail.facts !== null
                    width: parent.width
                    spacing: 4

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: detail.facts ? detail.facts.name + (page.selectedAlive ? "" : "   (ended)") : ""
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 17
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: detail.facts ? ["PID " + detail.facts.pid, detail.facts.proc, detail.facts.user,
                                              "started " + detail.facts.started, page.stateText(detail.facts.state),
                                              detail.facts.threads + (detail.facts.threads === 1 ? " thread" : " threads"),
                                              page.bytes(detail.facts.memory)].join("  ·  ") : ""
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                }

                // why it is tagged
                Text {
                    textFormat: Text.PlainText
                    visible: page.selectedFlag !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: page.flagText(page.selectedFlag) + " — " + page.flagHint(page.selectedFlag)
                    color: page.selectedFlag === "anr" || page.selectedFlag === "stuck" ? Theme.alert : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                Rectangle {
                    visible: detail.facts !== null && page.showWhy
                    width: parent.width
                    height: 1
                    color: Theme.line
                }

                Text {
                    textFormat: Text.PlainText
                    visible: detail.facts !== null && page.showWhy
                    text: "WHY IT RUNS"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                Repeater {
                    model: page.showWhy && page.info && page.info.lines ? page.info.lines : []

                    delegate: Item {
                        required property var modelData

                        width: detailBody.width
                        height: Math.max(20, reasonText.implicitHeight)

                        Text {
                            id: reasonGlyph

                            textFormat: Text.PlainText
                            width: 22
                            text: page.kindGlyph(parent.modelData.kind)
                            color: parent.modelData.kind === "core" || parent.modelData.kind === "kernel" ? Theme.alert : Theme.accent
                            font.family: parent.modelData.kind === "yakushi" ? Theme.mono : Theme.glyphs
                            font.pixelSize: 14
                        }

                        Text {
                            id: reasonText

                            textFormat: Text.PlainText
                            anchors.left: reasonGlyph.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            wrapMode: Text.Wrap
                            text: parent.modelData.text
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12
                            lineHeight: 1.2
                        }
                    }
                }

                // the program itself
                Column {
                    visible: detail.facts !== null && page.showWhy
                    width: parent.width
                    spacing: 4
                    topPadding: 4

                    Text {
                        textFormat: Text.PlainText
                        text: "PROGRAM"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: detail.facts ? (detail.facts.script || detail.facts.program || "—") : ""
                        color: Theme.inkSoft
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }

                    Text {
                        textFormat: Text.PlainText
                        topPadding: 4
                        text: "COMMAND"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: detail.facts ? (detail.facts.command || "—") : ""
                        color: Theme.inkSoft
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // ---- remove a package: over everything below the title
    RemovePanel {
        id: remover

        hostWindow: page.hostWindow

        visible: page.removing
        anchors.top: rule.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 30
        onClosed: page.removing = false
    }
}

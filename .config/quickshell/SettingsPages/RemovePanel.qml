import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Tasks -> remove a package, without leaving anything behind.
// Three views: "search" (pick an installed package), "plan" (everything
// removing it would do, nothing changed yet) and "removed" (earlier
// removals, with UNDO). scripts/yakushi-removectl.py does the work: one
// password prompt, pacman -Rns, your files moved to the Yakushi trash.
Rectangle {
    id: panel

    signal closed()

    property var hostWindow: null

    // your password is asked right here, in the footer (no dialog behind
    // Settings); it goes to sudo through a pipe and is not kept
    property string pending: ""          // "remove" or "undo:<id>" waiting for the password
    property string secret: ""           // only between "OK" and the helper starting

    function askPassword(what) {
        pending = what
        passwordRow.error = ""
        Qt.callLater(passwordRow.open)
    }

    function withPassword(pw) {
        var what = pending
        pending = ""
        secret = pw
        if (what === "remove") {
            note = "Removing…"
            noteOk = true
            doJob.stdinEnabled = true
            doJob.command = ["python3", helper, "--password-stdin", "remove",
                             JSON.stringify({ target: target, cascade: cascade, files: chosenFiles() })]
            doJob.running = true
        } else if (what.indexOf("undo:") === 0) {
            note = "Putting it back… (reinstalling needs the internet)"
            noteOk = true
            trashJob.stdinEnabled = true
            trashJob.command = ["python3", helper, "--password-stdin", "undo", what.slice(5)]
            trashJob.running = true
        }
    }

    function giveSecret(job) {
        job.write(secret + "\n")
        secret = ""
        job.stdinEnabled = false          // closes its stdin
    }

    function wrongPassword(what) {
        askPassword(what)
        passwordRow.error = "Wrong password. Try again."
        note = ""
    }

    readonly property string helper: (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-removectl.py"

    property string view: "search"       // search | plan | removed
    property string query: ""
    property string scope: "mine"         // mine (installed by you) | all | unused
    property var counts: ({})
    property var found: []
    property int foundTotal: 0
    property var plan: null
    property var target: []
    property bool cascade: false
    property var unticked: ({})         // files you unticked: path -> true
    property var history: []
    property string note: ""
    property bool noteOk: true
    property string armed: ""           // "remove" or "empty:<id>" waiting for a second click
    property bool done: false           // the plan was carried out
    property string doneId: ""

    readonly property bool working: searchJob.running || planJob.running || doJob.running || trashJob.running

    color: Theme.surface
    border.width: 1
    border.color: Theme.tint(Theme.accent, 0.5)

    // ---- entry points (TasksPage calls these)
    function openSearch(text) {
        pending = ""
        view = "search"
        note = ""
        query = text || ""
        searchBox.text = query
        runSearch()
    }

    function openFirst() {
        for (var i = 0; i < found.length; i++)
            if (found[i].protected === "") {
                openPlan([found[i].name])
                return
            }
    }

    function openPlan(names) {
        pending = ""
        view = "plan"
        target = names
        cascade = false
        unticked = {}
        done = false
        doneId = ""
        armed = ""
        note = ""
        plan = null
        runPlan()
    }

    function openRemoved() {
        pending = ""
        view = "removed"
        note = ""
        armed = ""
        trashJob.command = ["python3", helper, "removed"]
        trashJob.running = true
    }

    // ---- helper calls
    function runSearch() {
        if (searchJob.running)
            return
        searchJob.command = ["python3", helper, "search", query, scope]
        searchJob.running = true
    }

    function runPlan() {
        plan = null
        planJob.command = ["python3", helper, "plan", JSON.stringify({ target: target, cascade: cascade })]
        planJob.running = true
    }

    function chosenFiles() {
        if (!plan || !plan.files)
            return []
        return plan.files.filter(function(f) { return panel.ticked(f) }).map(function(f) { return f.path })
    }

    function ticked(f) {
        var u = unticked[f.path]
        return u === undefined ? f.checked : !u
    }

    function toggle(f) {
        var copy = Object.assign({}, unticked)
        copy[f.path] = ticked(f)
        unticked = copy
    }

    function doRemove() {
        if (!plan || !plan.canRemove || working || done)
            return
        if (armed !== "remove") {
            armed = "remove"
            disarm.restart()
            return
        }
        armed = ""
        note = ""
        askPassword("remove")
    }

    function undo(id) {
        if (working)
            return
        note = ""
        askPassword("undo:" + id)
    }

    function empty(id) {
        if (working)
            return
        if (armed !== "empty:" + id) {
            armed = "empty:" + id
            disarm.restart()
            return
        }
        armed = ""
        trashJob.command = ["python3", helper, "empty", id]
        trashJob.running = true
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: panel.armed = ""
    }

    Timer {
        id: searchDelay
        interval: 250
        onTriggered: panel.runSearch()
    }

    // how many are in the Yakushi trash (for REMOVED BEFORE (n))
    Component.onCompleted: {
        trashJob.command = ["python3", helper, "removed"]
        trashJob.running = true
    }

    onScopeChanged: runSearch()

    function parse(text) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return { ok: false, message: "No answer from the helper." }
        }
    }

    Process {
        id: searchJob
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                panel.found = d.packages || []
                panel.counts = d.counts || panel.counts
                panel.foundTotal = d.total || 0
                if (d.ok === false)
                    panel.say(d.message, false)
                if (searchBox.text !== panel.query)        // typed on while it ran
                    searchDelay.restart()
            }
        }
    }

    Process {
        id: planJob
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.ok === false) {
                    panel.say(d.message, false)
                    panel.plan = { failed: true }
                } else {
                    panel.plan = d
                }
            }
        }
    }

    Process {
        id: doJob

        onStarted: if (stdinEnabled) panel.giveSecret(doJob)
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.wrongPassword) {
                    panel.wrongPassword("remove")
                    return
                }
                panel.say(d.message || "", d.ok !== false)
                if (d.ok !== false) {
                    panel.done = true
                    panel.doneId = d.id || ""
                    trashJob.command = ["python3", panel.helper, "removed"]     // the count on top
                    Qt.callLater(function() { if (!trashJob.running) trashJob.running = true })
                }
            }
        }
    }

    Process {
        id: trashJob

        onStarted: if (stdinEnabled) panel.giveSecret(trashJob)
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.removed !== undefined) {
                    panel.history = d.removed
                    return
                }
                if (d.wrongPassword) {
                    panel.wrongPassword("undo:" + trashJob.command[trashJob.command.length - 1])
                    return
                }
                panel.say(d.message || "", d.ok !== false)
                if (panel.view === "removed") {
                    trashJob.command = ["python3", panel.helper, "removed"]
                    Qt.callLater(function() { trashJob.running = true })
                } else if (d.ok !== false) {
                    panel.done = false        // undone from the result view
                    panel.doneId = ""
                    panel.plan = null
                    panel.view = "removed"
                    trashJob.command = ["python3", panel.helper, "removed"]
                    Qt.callLater(function() { trashJob.running = true })
                }
            }
        }
    }

    function say(text, ok) {
        note = text
        noteOk = ok
    }

    function bytes(n) {
        if (!n)
            return "0 KB"
        if (n >= 1073741824)
            return (n / 1073741824).toFixed(1) + " GB"
        if (n >= 1048576)
            return Math.round(n / 1048576) + " MB"
        return Math.max(1, Math.round(n / 1024)) + " KB"
    }

    readonly property real filesSize: {
        var t = 0
        if (plan && plan.files)
            for (var i = 0; i < plan.files.length; i++)
                if (ticked(plan.files[i]))
                    t += plan.files[i].size
        return t
    }

    // ---- small parts (kept free of outer ids)
    component Caption: Text {
        textFormat: Text.PlainText
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
        topPadding: 6
    }

    component Plain: Text {
        textFormat: Text.PlainText
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
        lineHeight: 1.15
    }

    component Pill: Rectangle {
        id: pill

        property string label: ""
        property bool danger: false
        property bool hot: false
        property bool on: true

        signal clicked()

        width: pillText.implicitWidth + 26
        height: 32
        opacity: on ? 1 : 0.4
        color: hot ? Theme.tint(Theme.alert, 0.3)
            : danger ? (pillMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, pillMouse.containsMouse ? 0.26 : 0.12)
        border.width: 1
        border.color: danger || hot ? Theme.alert : Theme.tint(Theme.accent, 0.7)

        Text {
            id: pillText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: pill.label
            color: pill.danger || pill.hot ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: pillMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: pill.on
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    // swallow clicks so the list behind does not get them
    MouseArea {
        anchors.fill: parent
    }

    // ---- header: title, view switch, close
    Item {
        id: top

        x: 20
        y: 16
        width: parent.width - 40
        height: 32

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.view === "search" ? "REMOVE A PACKAGE"
                : panel.view === "removed" ? "REMOVED BEFORE"
                : "REMOVE " + panel.target.join(", ").toUpperCase()
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 15
            font.letterSpacing: 3
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Pill {
                visible: panel.view !== "search"
                label: "PACKAGES"
                onClicked: panel.openSearch(panel.query)
            }

            Pill {
                visible: panel.view !== "removed"
                label: "REMOVED BEFORE" + (panel.history.length ? "  " + panel.history.length : "")
                onClicked: panel.openRemoved()
            }

            Pill {
                label: "CLOSE"
                onClicked: panel.closed()
            }
        }
    }

    Rectangle {
        id: topRule

        anchors.top: top.bottom
        anchors.topMargin: 14
        x: 20
        width: parent.width - 40
        height: 1
        color: Theme.line
    }

    // ---- footer: what happened / the big button
    Item {
        id: foot

        anchors.bottom: parent.bottom
        x: 20
        width: parent.width - 40
        height: 64

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
        }

        PasswordRow {
            id: passwordRow

            visible: panel.pending !== ""
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: panel.pending === "remove" ? "Your password, to remove " + panel.target.join(", ")
                : "Your password, to put it back"
            action: panel.pending === "remove" ? "REMOVE" : "UNDO"
            onAccepted: password => panel.withPassword(password)
            onCanceled: {
                panel.pending = ""
                panel.note = "Cancelled. Nothing was changed."
                panel.noteOk = true
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: panel.pending === ""
            anchors.left: parent.left
            anchors.right: footButtons.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: panel.note !== "" ? panel.note
                : panel.armed === "remove" ? "Click REMOVE again; then your password is asked here."
                : panel.view === "plan" && panel.plan && panel.plan.canRemove
                    ? "Frees about " + panel.bytes((panel.plan.freed || 0) + panel.filesSize)
                      + ". Your files go to the Yakushi trash: UNDO can bring everything back."
                : panel.view === "search" ? "Pick a package to see what removing it would do. Nothing changes yet."
                : panel.view === "removed" ? "UNDO reinstalls the packages and puts your files and services back."
                : ""
            color: panel.note !== "" ? (panel.noteOk ? Theme.ink : Theme.alert)
                : panel.armed !== "" ? Theme.alert : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
        }

        Row {
            id: footButtons

            visible: panel.pending === ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Pill {
                visible: panel.view === "plan" && panel.done && panel.doneId !== ""
                label: "UNDO"
                on: !panel.working
                onClicked: panel.undo(panel.doneId)
            }

            Pill {
                visible: panel.view === "plan" && !panel.done
                label: panel.armed === "remove" ? "CLICK AGAIN" : panel.working ? "REMOVING…" : "REMOVE"
                danger: true
                hot: panel.armed === "remove"
                on: panel.plan !== null && panel.plan.canRemove === true && !panel.working
                onClicked: panel.doRemove()
            }
        }
    }

    // ---- the body
    Flickable {
        id: body

        anchors.top: topRule.bottom
        anchors.topMargin: 14
        anchors.bottom: foot.top
        anchors.bottomMargin: 8
        x: 20
        width: parent.width - 40
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: body.width
            spacing: 10

            // ================= search =================
            Rectangle {
                visible: panel.view === "search"
                width: parent.width
                height: 34
                color: Theme.tint(Theme.ink, 0.03)
                border.width: 1
                border.color: searchBox.activeFocus ? Theme.accent : Theme.line

                TextInput {
                    id: searchBox

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    focus: panel.view === "search"
                    Keys.onReturnPressed: panel.openFirst()
                    Keys.onEnterPressed: panel.openFirst()
                    onTextChanged: {
                        panel.query = text
                        searchDelay.restart()
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: searchBox.text === "" && !searchBox.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search installed packages by name or description"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                }
            }

            Item {
                visible: panel.view === "search"
                width: parent.width
                height: 32

                Row {
                    id: scopes

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [["mine", "YOU INSTALLED"], ["unused", "UNUSED"], ["all", "ALL"]]

                        delegate: Rectangle {
                            id: scopeChip

                            required property var modelData
                            readonly property bool on: panel.scope === modelData[0]
                            readonly property var count: panel.counts[modelData[0]]

                            width: scopeText.implicitWidth + 22
                            height: 28
                            color: on ? Theme.tint(Theme.accent, 0.16) : scopeMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : "transparent"
                            border.width: 1
                            border.color: on ? Theme.accent : Theme.line

                            Text {
                                id: scopeText

                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: scopeChip.modelData[1] + (scopeChip.count !== undefined ? "  " + scopeChip.count : "")
                                color: scopeChip.on ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: scopeMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.scope = scopeChip.modelData[0]
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: scopes.right
                    anchors.leftMargin: 14
                    anchors.right: removeUnused.visible ? removeUnused.left : parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: panel.scope === "unused" && panel.found.length === 0 && !searchJob.running
                        ? "Nothing unused: clean."
                        : panel.foundTotal > panel.found.length
                            ? "showing " + panel.found.length + " of " + panel.foundTotal + " · type to narrow it down"
                        : panel.scope === "unused" ? "dependencies nothing needs any more"
                        : "Enter opens the first one"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 10
                }

                Pill {
                    id: removeUnused

                    visible: panel.scope === "unused" && panel.found.filter(function(p) { return p.protected === "" }).length > 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "REMOVE ALL UNUSED"
                    danger: true
                    onClicked: panel.openPlan(panel.found.filter(function(p) { return p.protected === "" }).map(function(p) { return p.name }))
                }
            }

            Repeater {
                model: panel.view === "search" ? panel.found : []

                delegate: Rectangle {
                    id: pkgRow

                    required property var modelData

                    width: column.width
                    height: 46
                    color: pkgMouse.containsMouse && modelData.protected === "" ? Theme.tint(Theme.ink, 0.05) : Theme.card
                    border.width: 1
                    border.color: Theme.line
                    opacity: modelData.protected !== "" ? 0.55 : 1

                    Text {
                        id: pkgName

                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.bottom: parent.verticalCenter
                        anchors.right: pkgTag.left
                        anchors.rightMargin: 12
                        elide: Text.ElideRight
                        text: pkgRow.modelData.name
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.verticalCenter
                        anchors.topMargin: 3
                        anchors.right: pkgTag.left
                        anchors.rightMargin: 12
                        elide: Text.ElideRight
                        text: pkgRow.modelData.protected !== "" ? "Protected: " + pkgRow.modelData.protected
                            : pkgRow.modelData.desc + (pkgRow.modelData.neededCount > 0
                                ? "   ·   needed by " + pkgRow.modelData.neededBy.join(", ")
                                  + (pkgRow.modelData.neededCount > 3 ? " +" + (pkgRow.modelData.neededCount - 3) : "")
                                : "")
                        color: pkgRow.modelData.protected !== "" ? Theme.alert : Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }

                    Text {
                        id: pkgTag

                        textFormat: Text.PlainText
                        anchors.right: pkgSize.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: pkgRow.modelData.explicit ? "YOU INSTALLED"
                            : pkgRow.modelData.neededCount === 0 ? "UNUSED" : "DEPENDENCY"
                        color: pkgRow.modelData.explicit ? Theme.accent
                            : pkgRow.modelData.neededCount === 0 ? Theme.alert : Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }

                    Text {
                        id: pkgSize

                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        horizontalAlignment: Text.AlignRight
                        text: panel.bytes(pkgRow.modelData.size)
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: pkgMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: pkgRow.modelData.protected === ""
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.openPlan([pkgRow.modelData.name])
                    }
                }
            }

            // ================= plan =================
            Plain {
                visible: panel.view === "plan" && panel.plan === null
                text: "Working out what removing it would do… (nothing is changed)"
                color: Theme.inkSoft
            }

            // it could not be worked out
            Column {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.failed === true
                width: parent.width
                spacing: 12

                Plain {
                    color: Theme.alert
                    text: "This could not be planned: " + panel.note
                }

                Pill {
                    label: "BACK"
                    onClicked: panel.openSearch(panel.query)
                }
            }

            // one line: what happens
            Rectangle {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.canRemove === true && !panel.done
                width: parent.width
                height: summary.implicitHeight + 22
                color: Theme.tint(Theme.accent, 0.08)
                border.width: 1
                border.color: Theme.tint(Theme.accent, 0.4)

                Plain {
                    id: summary

                    x: 12
                    y: 11
                    width: parent.width - 24
                    text: {
                        var p = panel.plan
                        if (!p || !p.remove)
                            return ""
                        var n = p.remove.length
                        var files = panel.chosenFiles().length
                        var bits = [n + (n === 1 ? " package goes" : " packages go")]
                        if (p.running && p.running.length)
                            bits.push(p.running.length + " running " + (p.running.length === 1 ? "process closes" : "processes close"))
                        if (p.units && p.units.system.length + p.units.user.length)
                            bits.push((p.units.system.length + p.units.user.length) + " service(s) turned off")
                        if (files)
                            bits.push(files + (files === 1 ? " file" : " files") + " to the Yakushi trash")
                        bits.push("about " + panel.bytes((p.freed || 0) + panel.filesSize) + " freed")
                        return bits.join("  ·  ")
                    }
                }
            }

            // other programs need it
            Column {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.blocked !== undefined
                         && Object.keys(panel.plan.blocked).length > 0
                width: parent.width
                spacing: 8

                Caption { text: "OTHER PROGRAMS NEED IT" }

                Repeater {
                    model: panel.plan && panel.plan.blocked ? Object.keys(panel.plan.blocked) : []

                    delegate: Plain {
                        required property var modelData
                        text: modelData + " is needed by " + panel.plan.blocked[modelData].join(", ") + "."
                    }
                }

                Plain {
                    text: "Removing it alone would break them. Remove them too, or keep it."
                    color: Theme.inkSoft
                }

                Row {
                    spacing: 8

                    Pill {
                        label: "REMOVE THEM TOO"
                        danger: true
                        on: !panel.working
                        onClicked: {
                            panel.cascade = true
                            panel.runPlan()
                        }
                    }

                    Pill {
                        label: "KEEP IT"
                        onClicked: panel.openSearch(panel.query)
                    }
                }
            }

            // protected: never here
            Rectangle {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.protected !== undefined
                         && panel.plan.protected.length > 0
                width: parent.width
                height: protectedText.implicitHeight + 24
                color: Theme.tint(Theme.alert, 0.12)
                border.width: 1
                border.color: Theme.tint(Theme.alert, 0.6)

                Plain {
                    id: protectedText

                    x: 12
                    y: 12
                    width: parent.width - 24
                    color: Theme.alert
                    text: panel.plan && panel.plan.protected
                        ? "This cannot be removed here: " + panel.plan.protected.map(function(g) { return g.name + " (" + g.reason + ")" }).join(", ") + "."
                        : ""
                }
            }

            // what goes
            Column {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.remove !== undefined && panel.plan.remove.length > 0
                width: parent.width
                spacing: 6

                Caption { text: panel.done ? "REMOVED" : "PACKAGES THAT GO" }

                Repeater {
                    model: panel.plan && panel.plan.remove ? panel.plan.remove : []

                    delegate: Rectangle {
                        id: goRow

                        required property var modelData

                        width: column.width
                        height: 40
                        color: Theme.card
                        border.width: 1
                        border.color: Theme.line

                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: goWhy.left
                            anchors.rightMargin: 12
                            elide: Text.ElideRight
                            text: goRow.modelData.name + (goRow.modelData.desc ? "  —  " + goRow.modelData.desc : "")
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12
                        }

                        Text {
                            id: goWhy

                            textFormat: Text.PlainText
                            anchors.right: goSize.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: goRow.modelData.why
                            color: goRow.modelData.why === "you chose it" ? Theme.accent : Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }

                        Text {
                            id: goSize

                            textFormat: Text.PlainText
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 70
                            horizontalAlignment: Text.AlignRight
                            text: panel.bytes(goRow.modelData.size)
                            color: Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Yakushi features that stop working / cannot be undone
            Repeater {
                model: panel.view === "plan" && panel.plan && panel.plan.soft ? panel.plan.soft : []

                delegate: Plain {
                    required property var modelData
                    color: Theme.alert
                    text: "Yakushi uses " + modelData.name + " for " + modelData.reason + ": that stops working."
                }
            }

            Plain {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.notInRepos !== undefined
                         && panel.plan.notInRepos.length > 0 && !panel.done
                color: Theme.alert
                text: panel.plan && panel.plan.notInRepos
                    ? "Not in the official repositories: " + panel.plan.notInRepos.join(", ")
                      + ". UNDO can put your files back, but cannot reinstall " + (panel.plan.notInRepos.length === 1 ? "it." : "them.")
                    : ""
            }

            // running, services, config
            Column {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.running !== undefined
                         && (panel.plan.running.length > 0 || panel.plan.units.system.length > 0
                             || panel.plan.units.user.length > 0 || panel.plan.mentions.length > 0)
                width: parent.width
                spacing: 6

                Caption { text: "ALSO" }

                Plain {
                    visible: panel.plan !== null && panel.plan.running !== undefined && panel.plan.running.length > 0
                    text: panel.plan && panel.plan.running
                        ? "Closed: " + panel.plan.running.map(function(p) { return p.name + " (PID " + p.pid + ")" }).join(", ") + "."
                        : ""
                }

                Plain {
                    visible: panel.plan !== null && panel.plan.units !== undefined
                             && panel.plan.units.system.length + panel.plan.units.user.length > 0
                    text: panel.plan && panel.plan.units
                        ? "Turned off: " + panel.plan.units.system.concat(panel.plan.units.user).join(", ") + "."
                        : ""
                }

                Repeater {
                    model: panel.plan && panel.plan.mentions ? panel.plan.mentions : []

                    delegate: Plain {
                        required property var modelData
                        color: Theme.inkSoft
                        text: modelData
                    }
                }
            }

            // your files
            Column {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.files !== undefined && panel.plan.files.length > 0
                width: parent.width
                spacing: 6

                Caption { text: panel.done ? "YOUR FILES" : "YOUR FILES  ·  ticked ones go to the Yakushi trash" }

                Repeater {
                    model: panel.plan && panel.plan.files ? panel.plan.files : []

                    delegate: Rectangle {
                        id: fileRow

                        required property var modelData
                        readonly property bool on: panel.ticked(modelData)

                        width: column.width
                        height: fileRow.modelData.note ? 46 : 38
                        color: fileMouse.containsMouse && !panel.done ? Theme.tint(Theme.ink, 0.05) : Theme.card
                        border.width: 1
                        border.color: Theme.line

                        Rectangle {
                            id: box

                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            color: fileRow.on ? Theme.accent : "transparent"
                            border.width: 1
                            border.color: fileRow.on ? Theme.accent : Theme.lineHot

                            Text {
                                textFormat: Text.PlainText
                                visible: fileRow.on
                                anchors.centerIn: parent
                                text: "✓"
                                color: Theme.surface
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Text {
                            id: filePath

                            textFormat: Text.PlainText
                            anchors.left: box.right
                            anchors.leftMargin: 12
                            anchors.right: fileSize.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: fileRow.modelData.note ? undefined : parent.verticalCenter
                            anchors.bottom: fileRow.modelData.note ? parent.verticalCenter : undefined
                            elide: Text.ElideMiddle
                            text: fileRow.modelData.path
                            color: fileRow.on ? Theme.ink : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 12
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: fileRow.modelData.note !== ""
                            anchors.left: filePath.left
                            anchors.right: filePath.right
                            anchors.top: parent.verticalCenter
                            anchors.topMargin: 3
                            elide: Text.ElideRight
                            text: fileRow.modelData.note
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }

                        Text {
                            id: fileSize

                            textFormat: Text.PlainText
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: (fileRow.modelData.partial ? "≥ " : "") + panel.bytes(fileRow.modelData.size)
                            color: Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: fileMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !panel.done && !panel.working
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.toggle(fileRow.modelData)
                        }
                    }
                }
            }

            Plain {
                visible: panel.view === "plan" && panel.plan !== null && panel.plan.files !== undefined
                         && panel.plan.files.length === 0 && panel.plan.canRemove
                color: Theme.inkSoft
                text: "No files of it were found in your home folder."
            }

            // ================= removed before =================
            Plain {
                visible: panel.view === "removed" && panel.history.length === 0
                color: Theme.inkSoft
                text: trashJob.running ? "Looking…" : "Nothing in the Yakushi trash."
            }

            Repeater {
                model: panel.view === "removed" ? panel.history : []

                delegate: Rectangle {
                    id: oldRow

                    required property var modelData

                    width: column.width
                    height: 58
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.line

                    Text {
                        id: oldName

                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.bottom: parent.verticalCenter
                        anchors.right: oldButtons.left
                        anchors.rightMargin: 12
                        elide: Text.ElideRight
                        text: oldRow.modelData.packages.map(function(p) { return p.name }).join(", ") || oldRow.modelData.target.join(", ")
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.verticalCenter
                        anchors.topMargin: 4
                        anchors.right: oldButtons.left
                        anchors.rightMargin: 12
                        elide: Text.ElideRight
                        text: new Date(oldRow.modelData.time * 1000).toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm")
                            + "  ·  " + oldRow.modelData.files.length + (oldRow.modelData.files.length === 1 ? " file kept" : " files kept")
                            + "  ·  " + panel.bytes(oldRow.modelData.freed)
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }

                    Row {
                        id: oldButtons

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Pill {
                            label: "UNDO"
                            on: !panel.working
                            onClicked: panel.undo(oldRow.modelData.id)
                        }

                        Pill {
                            label: panel.armed === "empty:" + oldRow.modelData.id ? "CLICK AGAIN" : "DELETE FOR GOOD"
                            danger: true
                            hot: panel.armed === "empty:" + oldRow.modelData.id
                            on: !panel.working
                            onClicked: panel.empty(oldRow.modelData.id)
                        }
                    }
                }
            }
        }
    }
}

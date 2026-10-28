import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Monitors
//
// Layout canvas (drag to arrange, snaps to edges), one expandable card per
// display (resolution, reload rate, scale, exact position) and display
// tools (backlight brightness, night light). Everything runs on demand:
// nothing polls while the page is open.
Item {
    id: page

    property var hostWindow: null
    clip: true

    property string homeDir: Quickshell.env("HOME") || ""
    property var displays: []
    property string openName: ""
    property int pickW: 0
    property int pickH: 0
    property real pickHz: 0
    property int planX: 0
    property int planY: 0
    property string note: "Loading displays..."
    property bool noteBad: false

    // Backlight: only laptops / panels with a backlight device have one.
    property bool hasBacklight: false
    property real backlight: 0.6
    property real warmth: 0.5
    property bool warmOn: false

    // Frozen while dragging so the canvas does not rescale under the pointer.
    property var frozenView: null

    readonly property int grid: 10
    readonly property int stick: 18
    readonly property var scales: [1.0, 1.25, 1.5, 1.75, 2.0]

    function glyph(code) {
        return String.fromCodePoint(code)
    }

    function monitorctl() {
        return homeDir + "/.config/hypr/scripts/yakushi-monitorctl.py"
    }

    function nightctl() {
        return homeDir + "/.config/hypr/scripts/yakushi-nightlightctl.py"
    }

    function displayNamed(name) {
        for (var i = 0; i < displays.length; ++i) {
            if (displays[i].name === name)
                return displays[i]
        }
        return null
    }

    function openDisplay() {
        return displayNamed(openName)
    }

    function openCard(name) {
        var mon = displayNamed(name)
        if (!mon)
            return

        openName = name
        pickW = mon.width
        pickH = mon.height
        pickHz = mon.refreshRate
        planX = mon.x
        planY = mon.y
    }

    function flipCard(name) {
        if (openName === name) {
            openName = ""
            return
        }
        openCard(name)
    }

    function hz(value) {
        var n = Number(value)
        return (Math.abs(n - Math.round(n)) < 0.05 ? Math.round(n) : n.toFixed(2)) + " Hz"
    }

    readonly property bool planDiffers: {
        var mon = openDisplay()
        return mon !== null && (mon.x !== planX || mon.y !== planY)
    }

    readonly property bool modeDiffers: {
        var mon = openDisplay()
        return mon !== null && (mon.width !== pickW
            || mon.height !== pickH
            || Math.abs(mon.refreshRate - pickHz) > 0.05)
    }

    // Name of a display the drafted position would overlap, if any.
    readonly property string clash: {
        var mon = openDisplay()
        if (!mon || !planDiffers)
            return ""
        for (var i = 0; i < displays.length; ++i) {
            var o = displays[i]
            if (o.name === mon.name)
                continue
            if (planX < o.x + o.logicalWidth && planX + mon.logicalWidth > o.x
                    && planY < o.y + o.logicalHeight && planY + mon.logicalHeight > o.y)
                return o.name
        }
        return ""
    }

    function pickedSize() {
        var mon = openDisplay()

        if (!mon)
            return null

        for (var i = 0; i < mon.resolutions.length; ++i) {
            var r = mon.resolutions[i]
            if (r.width === pickW && r.height === pickH)
                return r
        }

        return mon.resolutions.length > 0 ? mon.resolutions[0] : null
    }

    function pickSize(width, height, rates) {
        pickW = width
        pickH = height

        if (!rates || rates.length === 0) {
            pickHz = 0
            return
        }

        var best = rates[0]
        var bestDistance = Math.abs(best - pickHz)

        for (var i = 1; i < rates.length; ++i) {
            var distance = Math.abs(rates[i] - pickHz)
            if (distance < bestDistance) {
                best = rates[i]
                bestDistance = distance
            }
        }

        pickHz = best
    }

    function reload() {
        if (homeDir === "" || lister.running)
            return

        lister.command = ["python3", monitorctl(), "list"]
        lister.running = true
    }

    function ask(proc, args, message) {
        if (proc.running || homeDir === "")
            return

        noteBad = false
        note = message
        proc.command = ["python3", monitorctl()].concat(args)
        proc.running = true
    }

    function applyMode() {
        if (openName === "")
            return

        ask(modeJob, [
            "apply-mode",
            openName,
            String(pickW),
            String(pickH),
            String(pickHz)
        ], "Applying display mode...")
    }

    function applyScale(scale) {
        if (openName === "")
            return

        ask(scaleJob, ["set-scale", openName, scale.toFixed(2)], "Applying scale...")
    }

    function applyPlace(x, y) {
        if (openName === "")
            return

        var px = parseInt(x)
        var py = parseInt(y)

        if (isNaN(px) || isNaN(py)) {
            note = "X and Y must be whole numbers."
            noteBad = true
            return
        }

        planX = px
        planY = py
        ask(placeJob, ["set-position", openName, String(px), String(py)],
            "Applying display position...")
    }

    function dropPlan() {
        var mon = openDisplay()
        if (!mon)
            return
        planX = mon.x
        planY = mon.y
    }

    // ---------------- Night light / backlight ----------------
    // The night light slider runs from warm (left) to cool (right) over the
    // range yakushi-nightlightctl.py accepts.
    readonly property int warmestK: 2500
    readonly property int coolestK: 6500

    function kelvin(f) {
        return Math.round(warmestK + f * (coolestK - warmestK))
    }

    function warmthOf(k) {
        var f = (k - warmestK) / (coolestK - warmestK)
        return f < 0 ? 0 : f > 1 ? 1 : f
    }

    function night(args) {
        if (homeDir !== "" && !nightJob.running) {
            nightJob.command = ["python3", nightctl()].concat(args)
            nightJob.running = true
        }
    }

    function setWarmth(f) {
        warmth = f
        night(["temperature", String(kelvin(f))])
    }

    function flipNight() {
        night(warmOn ? ["off"] : ["set", String(kelvin(warmth))])
    }

    function setBacklight(f) {
        if (hasBacklight && !backlightWrite.running) {
            // keep at least 5 %: at 0 many panels switch off entirely
            backlightWrite.command = ["brightnessctl", "-c", "backlight", "set",
                                      Math.max(5, Math.round(f * 100)) + "%"]
            backlightWrite.running = true
        }
    }

    // ---------------- Canvas geometry ----------------
    function extent() {
        if (displays.length === 0)
            return { minX: 0, minY: 0, width: 1, height: 1 }

        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity

        for (var i = 0; i < displays.length; ++i) {
            var mon = displays[i]
            var px = mon.name === openName ? planX : mon.x
            var py = mon.name === openName ? planY : mon.y
            minX = Math.min(minX, px)
            minY = Math.min(minY, py)
            maxX = Math.max(maxX, px + mon.logicalWidth)
            maxY = Math.max(maxY, py + mon.logicalHeight)
        }

        return {
            minX: minX,
            minY: minY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        }
    }

    // Fit the whole arrangement into the canvas, centred, with room around it.
    function view(areaWidth, areaHeight) {
        if (frozenView)
            return frozenView

        var bounds = extent()
        var pad = 26
        var scale = Math.min(
            (areaWidth - pad * 2) / bounds.width,
            (areaHeight - pad * 2) / bounds.height
        )
        scale = Math.max(0.01, scale)

        return {
            minX: bounds.minX,
            minY: bounds.minY,
            scale: scale,
            offsetX: (areaWidth - bounds.width * scale) / 2,
            offsetY: (areaHeight - bounds.height * scale) / 2
        }
    }

    function boxFor(mon, areaWidth, areaHeight) {
        var t = view(areaWidth, areaHeight)
        var px = mon.name === openName ? planX : mon.x
        var py = mon.name === openName ? planY : mon.y

        return {
            x: t.offsetX + (px - t.minX) * t.scale,
            y: t.offsetY + (py - t.minY) * t.scale,
            w: Math.max(40, mon.logicalWidth * t.scale),
            h: Math.max(28, mon.logicalHeight * t.scale)
        }
    }

    function snap(monName, rawX, rawY) {
        var mon = displayNamed(monName)

        if (!mon)
            return { x: Math.round(rawX), y: Math.round(rawY) }

        var x = Math.round(rawX / grid) * grid
        var y = Math.round(rawY / grid) * grid
        var selfW = mon.logicalWidth
        var selfH = mon.logicalHeight

        for (var j = 0; j < displays.length; ++j) {
            var other = displays[j]

            if (other.name === monName)
                continue

            var xCandidates = [other.x, other.x + other.logicalWidth,
                               other.x - selfW, other.x + other.logicalWidth - selfW]
            var yCandidates = [other.y, other.y + other.logicalHeight,
                               other.y - selfH, other.y + other.logicalHeight - selfH]

            for (var xi = 0; xi < xCandidates.length; ++xi) {
                if (Math.abs(rawX - xCandidates[xi]) <= stick) {
                    x = Math.round(xCandidates[xi])
                    break
                }
            }

            for (var yi = 0; yi < yCandidates.length; ++yi) {
                if (Math.abs(rawY - yCandidates[yi]) <= stick) {
                    y = Math.round(yCandidates[yi])
                    break
                }
            }
        }

        return { x: x, y: y }
    }

    Component.onCompleted: {
        page.reload()
        backlightRead.running = true
        page.night(["status"])
    }

    // ---------------- Processes ----------------
    Process {
        id: lister

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (!data.ok) {
                        page.note = data.message
                        page.noteBad = true
                        return
                    }

                    page.displays = data.monitors

                    if (page.displayNamed(page.openName))
                        page.openCard(page.openName)
                    else
                        page.openName = ""

                    page.note = page.displays.length
                        + (page.displays.length === 1 ? " display detected." : " displays detected.")
                    page.noteBad = false
                } catch (e) {
                    page.note = "Could not parse display information."
                    page.noteBad = true
                }
            }
        }
    }

    // apply-mode / set-scale / set-position / restore all report the same way
    component Job: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.note = result.message
                    page.noteBad = !result.ok
                } catch (e) {
                    page.note = text.trim()
                    page.noteBad = true
                }
                reloadSoon.restart()
            }
        }
    }

    Job { id: modeJob }
    Job { id: scaleJob }
    Job { id: placeJob }
    Job { id: undoJob }

    Timer {
        id: reloadSoon
        interval: 350
        repeat: false
        onTriggered: page.reload()
    }

    // `brightnessctl -m` prints: device,class,now,percent,max
    Process {
        id: backlightRead

        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                var cols = text.trim().split(",")
                var pct = cols[1] === "backlight" ? parseInt(cols[3]) : NaN
                page.hasBacklight = !isNaN(pct)
                if (page.hasBacklight)
                    page.backlight = pct / 100
            }
        }
    }

    Process {
        id: backlightWrite
    }

    // yakushi-nightlightctl.py answers {ok, enabled, temperature[, message]}
    Process {
        id: nightJob

        stdout: StdioCollector {
            onStreamFinished: {
                var r = null
                try {
                    r = JSON.parse(text)
                } catch (e) {
                }
                if (!r) {
                    page.note = "Night light did not answer."
                    page.noteBad = true
                    return
                }
                page.warmOn = r.enabled === true
                if (!isNaN(Number(r.temperature)))
                    page.warmth = page.warmthOf(Number(r.temperature))
                if (r.ok === false) {
                    page.note = r.message || "Night light failed."
                    page.noteBad = true
                }
            }
        }
    }

    // ---------------- Small building blocks ----------------
    component SectionLabel: Text {
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    // Selectable pill (resolution, reload rate, scale)
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool selected: false
        property bool current: false     // what the display uses right now
        signal picked()

        width: Math.max(64, chipLabel.implicitWidth + 26)
        height: 30
        radius: Theme.rounded ? (8) : 0
        color: selected
            ? Theme.tint(Theme.accent, 0.16)
            : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.07) : Theme.tint(Theme.ink, 0.035)
        border.width: 1
        border.color: selected
            ? Theme.accent
            : chipMouse.containsMouse ? Theme.lineHot : Theme.tint(Theme.ink, 0.07)

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }

        Text {
            id: chipLabel

            anchors.centerIn: parent
            text: chip.label
            color: chip.selected ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
        }

        // Small dot marks the mode currently in use
        Rectangle {
            visible: chip.current && !chip.selected
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5
            width: 4
            height: 4
            radius: Theme.rounded ? (2) : 0
            color: Theme.accent
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component Act: Rectangle {
        id: act

        property string label: ""
        property bool primary: true
        property bool live: true
        signal activated()

        width: actText.implicitWidth + 30
        height: 32
        radius: Theme.rounded ? (8) : 0
        opacity: live ? 1 : 0.4
        color: !live
            ? "transparent"
            : actMouse.containsMouse
                ? Theme.tint(Theme.accent, primary ? 0.24 : 0.10)
                : (primary ? Theme.tint(Theme.accent, 0.14) : "transparent")
        border.width: 1
        border.color: primary && live ? Theme.accent : Theme.line

        Text {
            id: actText

            anchors.centerIn: parent
            text: act.label
            color: act.primary && act.live ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        MouseArea {
            id: actMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: act.live
            cursorShape: Qt.PointingHandCursor
            onClicked: act.activated()
        }
    }

    // ---------------- Header ----------------
    Item {
        id: head

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30

        PageTitle {
            anchors.left: parent.left
            anchors.right: headTools.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "MONITORS"
        }

        Row {
            id: headTools
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            HeaderButton {
                label: "RELOAD"
                icon: page.glyph(0xF0450)
                onActivated: page.reload()
            }

            HeaderButton {
                label: "UNDO LAST"
                icon: page.glyph(0xF054C)
                onActivated: page.ask(undoJob, ["restore"], "Restoring previous layout...")
            }
        }
    }

    Rectangle {
        id: headRule

        anchors.top: head.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Text {
        id: noteLine

        anchors.top: headRule.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 14
        text: page.note
        color: page.noteBad ? Theme.alert : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    ScrollHint {
        flick: scroller
    }

    Flickable {
        id: scroller

        anchors.top: noteLine.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: stack.height + 8
        boundsBehavior: Flickable.StopAtBounds
        // Dragging a monitor must not scroll the page.
        interactive: page.frozenView === null

        Column {
            id: stack

            width: scroller.width
            spacing: 14

            // ================= Layout =================
            Item {
                width: parent.width
                height: 14

                SectionLabel {
                    text: "LAYOUT"
                }

                Text {
                    anchors.right: parent.right
                    text: "Drag to arrange  ·  snaps to edges"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                }
            }

            Rectangle {
                id: board

                width: parent.width
                height: 250
                radius: Theme.rounded ? (10) : 0
                color: Theme.card
                border.width: 1
                border.color: Theme.line
                clip: true

                // Dot grid, painted once (repaints only when resized)
                Canvas {
                    anchors.fill: parent
                    opacity: 0.5

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = "#2a2a2a"
                        for (var x = 12; x < width; x += 18)
                            for (var y = 12; y < height; y += 18)
                                ctx.fillRect(x, y, 1.5, 1.5)
                    }
                }

                Item {
                    id: plane

                    anchors.fill: parent

                    Repeater {
                        model: page.displays

                        delegate: Rectangle {
                            id: box

                            required property var modelData

                            readonly property bool selected: page.openName === modelData.name
                            readonly property var geo: page.boxFor(
                                modelData, plane.width, plane.height)

                            // Glide into place after a drop or an applied change,
                            // but follow the pointer 1:1 while dragging.
                            readonly property bool animate: page.frozenView === null

                            x: geo.x
                            y: geo.y
                            width: geo.w
                            height: geo.h
                            z: selected ? 2 : 1

                            Behavior on x { enabled: box.animate; NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: box.animate; NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
                            Behavior on width { enabled: box.animate; NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
                            Behavior on height { enabled: box.animate; NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
                            radius: Theme.rounded ? (8) : 0
                            color: selected
                                ? Theme.tint(Theme.accent, grip.pressed ? 0.22 : 0.15)
                                : grip.containsMouse ? Theme.tint(Theme.ink, 0.08) : Theme.tint(Theme.ink, 0.045)
                            border.width: selected ? 2 : 1
                            border.color: selected
                                ? Theme.accent
                                : grip.containsMouse ? Theme.tint(Theme.ink, 0.30) : Theme.tint(Theme.ink, 0.16)

                            Behavior on color {
                                ColorAnimation { duration: Theme.tFast }
                            }

                            // Focused display marker
                            Rectangle {
                                visible: box.modelData.focused === true
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                width: 6
                                height: 6
                                radius: Theme.rounded ? (3) : 0
                                color: Theme.accent
                            }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 3
                                visible: parent.height > 44

                                Text {
                                    width: parent.width
                                    text: box.modelData.name
                                    color: Theme.ink
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: box.modelData.width + "×" + box.modelData.height
                                        + "  ·  " + page.hz(box.modelData.refreshRate)
                                    color: Theme.inkSoft
                                    font.family: Theme.mono
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: box.height > 72
                                    text: box.selected
                                        ? page.planX + ", " + page.planY
                                        : box.modelData.x + ", " + box.modelData.y
                                    color: box.selected && page.planDiffers ? Theme.accent : Theme.inkMute
                                    font.family: Theme.mono
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: grip

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                preventStealing: true

                                property real grabX: 0
                                property real grabY: 0
                                property real fromX: 0
                                property real fromY: 0

                                onPressed: function(mouse) {
                                    if (page.openName !== box.modelData.name)
                                        page.openCard(box.modelData.name)

                                    page.frozenView = page.view(plane.width, plane.height)

                                    var point = mapToItem(plane, mouse.x, mouse.y)
                                    grabX = point.x
                                    grabY = point.y
                                    fromX = page.planX
                                    fromY = page.planY
                                }

                                onPositionChanged: function(mouse) {
                                    if (!pressed || !page.frozenView)
                                        return

                                    var point = mapToItem(plane, mouse.x, mouse.y)
                                    var scale = page.frozenView.scale
                                    var snapped = page.snap(
                                        box.modelData.name,
                                        fromX + (point.x - grabX) / scale,
                                        fromY + (point.y - grabY) / scale)

                                    page.planX = snapped.x
                                    page.planY = snapped.y
                                }

                                onReleased: page.frozenView = null
                                onCanceled: page.frozenView = null
                            }
                        }
                    }
                }

                Text {
                    visible: page.displays.length === 0
                    anchors.centerIn: parent
                    text: "No displays reported by Hyprland."
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 10
                }

            }

            // Pending position: slides out under the canvas after a drag
            Item {
                width: parent.width
                height: page.planDiffers ? 40 : 0
                visible: height > 0
                clip: true

                Behavior on height {
                    NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: planRow.implicitWidth + 24
                    height: 40
                    radius: Theme.rounded ? (10) : 0
                    color: Theme.tint(Theme.surface, 0.94)
                    border.width: 1
                    border.color: Theme.tint(Theme.accent, 0.5)
                    opacity: page.planDiffers ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.tMid }
                    }

                    Row {
                        id: planRow

                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.clash !== ""
                                ? "Overlaps " + page.clash + "  ·  " + page.planX + ", " + page.planY
                                : page.openName + " → " + page.planX + ", " + page.planY
                            color: page.clash !== "" ? Theme.alert : Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }

                        Act {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 26
                            primary: false
                            label: "RESET"
                            onActivated: page.dropPlan()
                        }

                        Act {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 26
                            label: "APPLY"
                            live: !placeJob.running
                            onActivated: page.applyPlace(page.planX, page.planY)
                        }
                    }
                }
            }

            // ================= Displays =================
            SectionLabel {
                text: "DISPLAYS"
            }

            Column {
                width: parent.width
                spacing: 8

                Repeater {
                    model: page.displays

                    delegate: Rectangle {
                        id: entry

                        required property var modelData
                        readonly property var mon: modelData
                        readonly property bool expanded: page.openName === mon.name

                        width: parent.width
                        height: expanded ? 64 + 14 + details.implicitHeight + 16 : 64
                        radius: Theme.rounded ? (10) : 0
                        color: Theme.card
                        border.width: 1
                        border.color: expanded
                            ? Theme.tint(Theme.accent, 0.8)
                            : entryMouse.containsMouse ? Theme.lineHot : Theme.line
                        clip: true

                        Behavior on height {
                            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                        }

                        // ---------- Card header ----------
                        Item {
                            id: entryHead

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 64

                            Rectangle {
                                id: badge

                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                height: 38
                                radius: Theme.rounded ? (10) : 0
                                color: entry.expanded
                                    ? Theme.tint(Theme.accent, 0.16)
                                    : Theme.tint(Theme.ink, 0.05)

                                Text {
                                    anchors.centerIn: parent
                                    text: page.glyph(0xF0379)
                                    color: entry.expanded ? Theme.accent : Theme.inkSoft
                                    font.family: Theme.glyphs
                                    font.pixelSize: 18
                                }
                            }

                            Column {
                                anchors.left: badge.right
                                anchors.leftMargin: 12
                                anchors.right: chips.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Row {
                                    spacing: 8

                                    Text {
                                        text: entry.mon.name
                                        color: Theme.ink
                                        font.family: Theme.mono
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    Text {
                                        visible: entry.mon.focused === true
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "FOCUSED"
                                        color: Theme.accent
                                        font.family: Theme.mono
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: entry.mon.description !== ""
                                        ? entry.mon.description
                                        : (entry.mon.make + " " + entry.mon.model).trim()
                                    color: Theme.inkMute
                                    font.family: Theme.mono
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: chips

                                anchors.right: chevron.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Repeater {
                                    model: [
                                        entry.mon.width + "×" + entry.mon.height,
                                        page.hz(entry.mon.refreshRate),
                                        entry.mon.scale.toFixed(2) + "×"
                                    ]

                                    delegate: Rectangle {
                                        required property string modelData

                                        width: pillText.implicitWidth + 16
                                        height: 22
                                        radius: Theme.rounded ? (11) : 0
                                        color: Theme.tint(Theme.ink, 0.05)

                                        Text {
                                            id: pillText

                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            color: Theme.inkSoft
                                            font.family: Theme.mono
                                            font.pixelSize: 9
                                        }
                                    }
                                }
                            }

                            Text {
                                id: chevron

                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.glyph(0xF0140)
                                color: entry.expanded ? Theme.accent : Theme.inkSoft
                                font.family: Theme.glyphs
                                font.pixelSize: 16
                                rotation: entry.expanded ? 180 : 0

                                Behavior on rotation {
                                    NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                id: entryMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.flipCard(entry.mon.name)
                            }
                        }

                        Rectangle {
                            visible: entry.expanded
                            anchors.top: entryHead.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            height: 1
                            color: Theme.line
                        }

                        // ---------- Details ----------
                        Column {
                            id: details

                            visible: entry.expanded
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: entryHead.bottom
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.topMargin: 14
                            spacing: 10

                            SectionLabel {
                                text: "RESOLUTION"
                                font.pixelSize: 9
                            }

                            Flow {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: entry.expanded ? entry.mon.resolutions : []

                                    delegate: Chip {
                                        required property var modelData

                                        label: modelData.width + "×" + modelData.height
                                        selected: page.pickW === modelData.width
                                            && page.pickH === modelData.height
                                        current: entry.mon.width === modelData.width
                                            && entry.mon.height === modelData.height
                                        onPicked: page.pickSize(modelData.width, modelData.height,
                                            modelData.refreshRates)
                                    }
                                }
                            }

                            SectionLabel {
                                text: "REFRESH RATE"
                                font.pixelSize: 9
                            }

                            Flow {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: {
                                        if (!entry.expanded)
                                            return []
                                        var res = page.pickedSize()
                                        return res ? res.refreshRates : []
                                    }

                                    delegate: Chip {
                                        required property var modelData

                                        label: page.hz(modelData)
                                        selected: Math.abs(page.pickHz - modelData) < 0.05
                                        current: entry.mon.width === page.pickW
                                            && entry.mon.height === page.pickH
                                            && Math.abs(entry.mon.refreshRate - modelData) < 0.05
                                        onPicked: page.pickHz = Number(modelData)
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: 34

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.modeDiffers
                                        ? "Selected: " + page.pickW + "×" + page.pickH
                                            + " @ " + page.hz(page.pickHz)
                                        : "This is the current mode."
                                    color: page.modeDiffers ? Theme.ink : Theme.inkMute
                                    font.family: Theme.mono
                                    font.pixelSize: 9
                                }

                                Act {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "APPLY MODE"
                                    live: page.modeDiffers && !modeJob.running
                                    onActivated: page.applyMode()
                                }
                            }

                            SectionLabel {
                                text: "SCALE"
                                font.pixelSize: 9
                            }

                            Flow {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: {
                                        var list = page.scales.slice()
                                        var cur = entry.mon.scale
                                        var known = list.some(function(s) { return Math.abs(s - cur) < 0.01 })
                                        if (!known)
                                            list.push(cur)
                                        return list.sort(function(a, b) { return a - b })
                                    }

                                    delegate: Chip {
                                        required property var modelData

                                        label: Number(modelData).toFixed(2) + "×"
                                        selected: Math.abs(entry.mon.scale - modelData) < 0.01
                                        onPicked: if (!selected) page.applyScale(Number(modelData))
                                    }
                                }
                            }

                            SectionLabel {
                                text: "POSITION"
                                font.pixelSize: 9
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: ["X", "Y"]

                                    delegate: Rectangle {
                                        id: field

                                        required property string modelData

                                        width: 132
                                        height: 32
                                        radius: Theme.rounded ? (8) : 0
                                        color: Theme.surface
                                        border.width: 1
                                        border.color: coord.activeFocus ? Theme.accent : Theme.lineHot

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: field.modelData
                                            color: Theme.inkMute
                                            font.family: Theme.mono
                                            font.pixelSize: 9
                                        }

                                        TextInput {
                                            id: coord

                                            anchors.left: parent.left
                                            anchors.leftMargin: 28
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(field.modelData === "X" ? page.planX : page.planY)
                                            color: Theme.ink
                                            selectionColor: Theme.tint(Theme.accent, 0.4)
                                            font.family: Theme.mono
                                            font.pixelSize: 10
                                            selectByMouse: true
                                            validator: IntValidator { bottom: -32768; top: 32768 }

                                            onEditingFinished: {
                                                var v = parseInt(text)
                                                if (isNaN(v))
                                                    return
                                                if (field.modelData === "X")
                                                    page.planX = v
                                                else
                                                    page.planY = v
                                            }
                                        }
                                    }
                                }

                                Act {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "APPLY POSITION"
                                    live: page.planDiffers && !placeJob.running
                                    onActivated: page.applyPlace(page.planX, page.planY)
                                }
                            }
                        }
                    }
                }
            }

            // ================= Display tools =================
            SectionLabel {
                text: "DISPLAY TOOLS"
            }

            Rectangle {
                width: parent.width
                height: tools.implicitHeight + 28
                radius: Theme.rounded ? (10) : 0
                color: Theme.card
                border.width: 1
                border.color: Theme.line

                Column {
                    id: tools

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    Slider {
                        width: parent.width
                        visible: page.hasBacklight
                        label: "BRIGHTNESS  " + Math.round(page.backlight * 100) + "%"
                        icon: page.glyph(0xF00DF)
                        value: page.backlight
                        tint: Theme.accent

                        onSliding: function(value) {
                            page.backlight = Math.max(0.05, value)
                        }

                        onSettled: function(value) {
                            page.backlight = Math.max(0.05, value)
                            page.setBacklight(page.backlight)
                        }
                    }

                    Text {
                        visible: !page.hasBacklight
                        width: parent.width
                        text: "Brightness: no built-in backlight found — external displays are adjusted with their own buttons."
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.line
                    }

                    ToggleRow {
                        width: parent.width
                        icon: page.glyph(0xF0594)
                        label: "Night light"
                        checked: page.warmOn
                        available: !nightJob.running
                        onToggled: page.flipNight()
                    }

                    Slider {
                        width: parent.width
                        opacity: page.warmOn ? 1 : 0.45
                        label: "TEMPERATURE  " + page.kelvin(page.warmth) + " K"
                        icon: page.glyph(0xF050F)
                        value: page.warmth
                        tint: Theme.accent

                        onSliding: function(value) {
                            page.warmth = value
                        }

                        onSettled: function(value) {
                            page.setWarmth(value)
                        }
                    }

                    Item {
                        width: parent.width
                        height: 10

                        Text {
                            anchors.left: parent.left
                            text: "WARMER"
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 8
                            font.letterSpacing: 1
                        }

                        Text {
                            anchors.right: parent.right
                            text: "COOLER"
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 8
                            font.letterSpacing: 1
                        }
                    }
                }
            }
        }
    }
}

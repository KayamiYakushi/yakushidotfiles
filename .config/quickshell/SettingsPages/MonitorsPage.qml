import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property var hostWindow: null
    clip: true

    property string homeDir: Quickshell.env("HOME") || ""
    property var monitors: []
    property string selectedName: ""
    property int selectedWidth: 0
    property int selectedHeight: 0
    property real selectedRefresh: 0
    property int draftX: 0
    property int draftY: 0
    property string statusText: "Loading displays..."
    property bool statusError: false

    property real brightnessValue: 0.6
    property real nightlightValue: 0.5
    property bool nightlightEnabled: false

    readonly property int dragSnap: 10
    readonly property int edgeSnapThreshold: 18

    function helperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-monitorctl.py"
    }

    function nightlightHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-nightlightctl.py"
    }

    function currentMonitor() {
        for (var i = 0; i < monitors.length; ++i) {
            if (monitors[i].name === selectedName)
                return monitors[i]
        }
        return null
    }

    function openMonitor(name) {
        selectedName = name
        var mon = currentMonitor()

        if (!mon)
            return

        selectedWidth = mon.width
        selectedHeight = mon.height
        selectedRefresh = mon.refreshRate
        draftX = mon.x
        draftY = mon.y
    }

    function toggleMonitor(name) {
        if (selectedName === name) {
            selectedName = ""
            return
        }
        openMonitor(name)
    }

    function currentResolutionObject() {
        var mon = currentMonitor()

        if (!mon)
            return null

        for (var i = 0; i < mon.resolutions.length; ++i) {
            var r = mon.resolutions[i]
            if (r.width === selectedWidth && r.height === selectedHeight)
                return r
        }

        return mon.resolutions.length > 0 ? mon.resolutions[0] : null
    }

    function chooseResolution(width, height, rates) {
        selectedWidth = width
        selectedHeight = height

        if (!rates || rates.length === 0) {
            selectedRefresh = 0
            return
        }

        var best = rates[0]
        var bestDistance = Math.abs(best - selectedRefresh)

        for (var i = 1; i < rates.length; ++i) {
            var distance = Math.abs(rates[i] - selectedRefresh)
            if (distance < bestDistance) {
                best = rates[i]
                bestDistance = distance
            }
        }

        selectedRefresh = best
    }

    function refresh() {
        if (homeDir === "" || listProc.running)
            return

        listProc.command = ["python3", helperPath(), "list"]
        listProc.running = true
    }

    function applySelectedMode() {
        if (applyModeProc.running || selectedName === "")
            return

        statusError = false
        statusText = "Applying display mode..."

        applyModeProc.command = [
            "python3",
            helperPath(),
            "apply-mode",
            selectedName,
            String(selectedWidth),
            String(selectedHeight),
            String(selectedRefresh)
        ]
        applyModeProc.running = true
    }

    function applyScale(scale) {
        if (scaleProc.running || selectedName === "")
            return

        scaleProc.command = [
            "python3",
            helperPath(),
            "set-scale",
            selectedName,
            scale.toFixed(2)
        ]
        scaleProc.running = true
    }

    function applyPosition(x, y) {
        if (positionProc.running || selectedName === "")
            return

        var px = parseInt(x)
        var py = parseInt(y)

        if (isNaN(px) || isNaN(py)) {
            statusText = "X and Y must be whole numbers."
            statusError = true
            return
        }

        draftX = px
        draftY = py
        statusText = "Applying display position..."
        statusError = false

        positionProc.command = [
            "python3",
            helperPath(),
            "set-position",
            selectedName,
            String(px),
            String(py)
        ]
        positionProc.running = true
    }

    function nightlightTemperature(value) {
        return Math.round(2500 + value * 4000)
    }

    function nightlightValueForTemperature(temperature) {
        return Math.max(0, Math.min(1, (temperature - 2500) / 4000))
    }

    function syncNightlightState(result) {
        if (!result)
            return

        page.nightlightEnabled = Boolean(result.enabled)

        var temperature = Number(result.temperature)
        if (!isNaN(temperature))
            page.nightlightValue = nightlightValueForTemperature(temperature)

        if (result.ok === false) {
            page.statusText = result.message || "Night Light command failed."
            page.statusError = true
        }
    }

    function runNightlightCommand(args) {
        if (homeDir === "" || nightlightProcess.running)
            return

        var command = ["python3", nightlightHelperPath()]
        for (var i = 0; i < args.length; ++i)
            command.push(args[i])

        nightlightProcess.command = command
        nightlightProcess.running = true
    }

    function loadNightlightState() {
        runNightlightCommand(["status"])
    }

    function nightlightOn() {
        runNightlightCommand([
            "set",
            String(nightlightTemperature(nightlightValue))
        ])
    }

    function nightlightOff() {
        runNightlightCommand(["off"])
    }

    function commitNightlight(value) {
        nightlightValue = value
        runNightlightCommand([
            "temperature",
            String(nightlightTemperature(value))
        ])
    }

    function commitBrightness(value) {
        brightnessSet.command = [
            "brightnessctl",
            "set",
            Math.round(value * 100) + "%"
        ]
        brightnessSet.running = true
    }

    function layoutMetrics() {
        if (monitors.length === 0) {
            return { minX: 0, minY: 0, width: 1, height: 1 }
        }

        var minX = monitors[0].x
        var minY = monitors[0].y
        var maxX = monitors[0].x + monitors[0].logicalWidth
        var maxY = monitors[0].y + monitors[0].logicalHeight

        for (var i = 1; i < monitors.length; ++i) {
            var mon = monitors[i]
            minX = Math.min(minX, mon.x)
            minY = Math.min(minY, mon.y)
            maxX = Math.max(maxX, mon.x + mon.logicalWidth)
            maxY = Math.max(maxY, mon.y + mon.logicalHeight)
        }

        return {
            minX: minX,
            minY: minY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        }
    }

    function mapTransform(areaWidth, areaHeight) {
        var bounds = layoutMetrics()
        var pad = 18
        var usableWidth = Math.max(1, areaWidth - pad * 2)
        var usableHeight = Math.max(1, areaHeight - pad * 2)
        var scale = Math.min(
            usableWidth / bounds.width,
            usableHeight / bounds.height
        )

        return {
            minX: bounds.minX,
            minY: bounds.minY,
            scale: scale,
            pad: pad
        }
    }

    function monitorMapRect(mon, areaWidth, areaHeight) {
        var t = mapTransform(areaWidth, areaHeight)
        var px = mon.name === selectedName ? draftX : mon.x
        var py = mon.name === selectedName ? draftY : mon.y
        var w = Math.max(60, mon.logicalWidth * t.scale)
        var h = Math.max(42, mon.logicalHeight * t.scale)
        var x = t.pad + (px - t.minX) * t.scale
        var y = t.pad + (py - t.minY) * t.scale

        x = Math.max(t.pad, Math.min(areaWidth - t.pad - w, x))
        y = Math.max(t.pad, Math.min(areaHeight - t.pad - h, y))

        return { x: x, y: y, w: w, h: h }
    }

    function snapPosition(monName, rawX, rawY) {
        var mon = null

        for (var i = 0; i < monitors.length; ++i) {
            if (monitors[i].name === monName) {
                mon = monitors[i]
                break
            }
        }

        if (!mon)
            return { x: Math.round(rawX), y: Math.round(rawY) }

        var x = Math.round(rawX / dragSnap) * dragSnap
        var y = Math.round(rawY / dragSnap) * dragSnap
        var selfW = mon.logicalWidth
        var selfH = mon.logicalHeight

        for (var j = 0; j < monitors.length; ++j) {
            var other = monitors[j]

            if (other.name === monName)
                continue

            var ox = other.x
            var oy = other.y
            var ow = other.logicalWidth
            var oh = other.logicalHeight

            var xCandidates = [
                ox,
                ox + ow,
                ox - selfW,
                ox + ow - selfW
            ]

            var yCandidates = [
                oy,
                oy + oh,
                oy - selfH,
                oy + oh - selfH
            ]

            for (var xi = 0; xi < xCandidates.length; ++xi) {
                if (Math.abs(rawX - xCandidates[xi]) <= edgeSnapThreshold) {
                    x = Math.round(xCandidates[xi])
                    break
                }
            }

            for (var yi = 0; yi < yCandidates.length; ++yi) {
                if (Math.abs(rawY - yCandidates[yi]) <= edgeSnapThreshold) {
                    y = Math.round(yCandidates[yi])
                    break
                }
            }
        }

        return { x: x, y: y }
    }

    Component.onCompleted: {
        page.refresh()
        brightnessGet.running = true
        page.loadNightlightState()
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (!data.ok) {
                        page.statusText = data.message
                        page.statusError = true
                        return
                    }

                    page.monitors = data.monitors

                    var stillExists = false

                    for (var i = 0; i < page.monitors.length; ++i) {
                        if (page.monitors[i].name === page.selectedName) {
                            stillExists = true
                            break
                        }
                    }

                    if (!stillExists) {
                        page.selectedName = ""
                    } else {
                        var mon = page.currentMonitor()
                        if (mon) {
                            page.selectedWidth = mon.width
                            page.selectedHeight = mon.height
                            page.selectedRefresh = mon.refreshRate
                            page.draftX = mon.x
                            page.draftY = mon.y
                        }
                    }

                    page.statusText = page.monitors.length
                        + (page.monitors.length === 1
                            ? " display detected."
                            : " displays detected.")
                    page.statusError = false
                } catch (e) {
                    page.statusText = "Could not parse display information."
                    page.statusError = true
                }
            }
        }
    }

    Process {
        id: applyModeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }
                refreshTimer.restart()
            }
        }
    }

    Process {
        id: scaleProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }
                refreshTimer.restart()
            }
        }
    }

    Process {
        id: positionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }
                refreshTimer.restart()
            }
        }
    }

    Process {
        id: restoreProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }
                refreshTimer.restart()
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 350
        repeat: false
        onTriggered: page.refresh()
    }

    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split(",")
                if (parts.length < 4)
                    return
                var pct = parseInt(parts[3])
                if (!isNaN(pct))
                    page.brightnessValue = pct / 100
            }
        }
    }

    Process { id: brightnessSet; stdout: StdioCollector {} stderr: StdioCollector {} }
    Process {
        id: nightlightProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.syncNightlightState(JSON.parse(text))
                } catch (e) {
                    page.statusText = "Night Light returned invalid state."
                    page.statusError = true
                }
            }
        }

        stderr: StdioCollector {}
    }

    Row {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30
        spacing: 8

        Text {
            text: "MONITORS"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.letterSpacing: 3
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: Math.max(0, parent.width - 360)
            height: 1
        }

        Rectangle {
            width: 92
            height: 30
            radius: Theme.radius
            color: reloadMouse.containsMouse
                ? Theme.alpha(Theme.accent, 0.10)
                : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: "RELOAD"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1
            }

            MouseArea {
                id: reloadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.refresh()
            }
        }

        Rectangle {
            width: 110
            height: 30
            radius: Theme.radius
            color: undoMouse.containsMouse
                ? Theme.alpha(Theme.accent, 0.10)
                : "transparent"
            border.width: 1
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: "UNDO LAST"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1
            }

            MouseArea {
                id: undoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (restoreProc.running)
                        return
                    restoreProc.command = [
                        "python3",
                        page.helperPath(),
                        "restore"
                    ]
                    restoreProc.running = true
                }
            }
        }
    }

    Rectangle {
        id: headerDivider
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.border
    }

    Text {
        id: statusLine
        anchors.top: headerDivider.bottom
        anchors.topMargin: 7
        anchors.left: parent.left
        anchors.right: parent.right
        height: 15
        text: page.statusText
        color: page.statusError ? Theme.danger : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Flickable {
        id: contentArea
        anchors.top: statusLine.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: contentColumn.height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentColumn
            width: contentArea.width - 8
            spacing: 12

            Text {
                text: "DISPLAY LAYOUT"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Rectangle {
                width: parent.width
                height: 178
                radius: Theme.radius
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.border

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.topMargin: 9
                    text: "Drag to draft a position. 10 px + edge snapping. Apply below."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                }

                Item {
                    id: mapArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 10
                    anchors.topMargin: 28
                    clip: true

                    Repeater {
                        model: page.monitors

                        delegate: Rectangle {
                            id: monitorRect
                            required property var modelData

                            property var rectData: page.monitorMapRect(
                                modelData,
                                mapArea.width,
                                mapArea.height
                            )

                            x: rectData.x
                            y: rectData.y
                            width: rectData.w
                            height: rectData.h
                            radius: Theme.radius
                            color: page.selectedName === modelData.name
                                ? Theme.alpha(Theme.accent, 0.13)
                                : Theme.alpha(Theme.textDim, 0.08)
                            border.width: page.selectedName === modelData.name ? 2 : 1
                            border.color: page.selectedName === modelData.name
                                ? Theme.accent
                                : Theme.borderAccent

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.width + "×" + modelData.height
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 7
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: (
                                        page.selectedName === modelData.name
                                            ? page.draftX + "×" + page.draftY
                                            : modelData.x + "×" + modelData.y
                                    )
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 7
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pressed
                                    ? Qt.ClosedHandCursor
                                    : Qt.OpenHandCursor

                                property real pressMapX: 0
                                property real pressMapY: 0
                                property real startX: 0
                                property real startY: 0

                                onPressed: function(mouse) {
                                    page.openMonitor(modelData.name)

                                    var point = mapToItem(
                                        mapArea,
                                        mouse.x,
                                        mouse.y
                                    )

                                    pressMapX = point.x
                                    pressMapY = point.y
                                    startX = page.draftX
                                    startY = page.draftY
                                }

                                onPositionChanged: function(mouse) {
                                    if (!pressed)
                                        return

                                    var point = mapToItem(
                                        mapArea,
                                        mouse.x,
                                        mouse.y
                                    )

                                    var t = page.mapTransform(
                                        mapArea.width,
                                        mapArea.height
                                    )

                                    var rawX = startX
                                        + (point.x - pressMapX) / t.scale
                                    var rawY = startY
                                        + (point.y - pressMapY) / t.scale

                                    var snapped = page.snapPosition(
                                        modelData.name,
                                        rawX,
                                        rawY
                                    )

                                    page.draftX = snapped.x
                                    page.draftY = snapped.y
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "DISPLAY DETAILS"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Column {
                width: parent.width
                spacing: 8

                Repeater {
                    model: page.monitors

                    delegate: Rectangle {
                        required property var modelData

                        property bool expanded: page.selectedName === modelData.name

                        width: parent.width
                        height: expanded
                            ? 56 + detailsColumn.implicitHeight + 24
                            : 56
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: expanded ? Theme.accent : Theme.border
                        clip: true

                        Behavior on height {
                            NumberAnimation { duration: Theme.animMed }
                        }

                        Rectangle {
                            id: cardHeader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 56
                            color: expanded
                                ? Theme.alpha(Theme.accent, 0.05)
                                : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    width: 34
                                    height: 22
                                    radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.alpha(Theme.textDim, 0.08)
                                    border.width: 1
                                    border.color: expanded
                                        ? Theme.accent
                                        : Theme.borderAccent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "▭"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }

                                Column {
                                    width: Math.max(170, parent.width - 190)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.width + "×" + modelData.height
                                            + "  " + modelData.refreshRate.toFixed(2) + " Hz"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: expanded ? "▴" : "▾"
                                    color: expanded ? Theme.accent : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.toggleMonitor(modelData.name)
                            }
                        }

                        Column {
                            id: detailsColumn
                            visible: expanded
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: cardHeader.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            spacing: 10

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: Theme.radius
                                color: Theme.alpha(Theme.textDim, 0.05)
                                border.width: 1
                                border.color: Theme.border

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 18

                                    Text {
                                        width: Math.max(220, parent.width * 0.58)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.description !== ""
                                            ? modelData.description
                                            : modelData.name
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "SCALE " + modelData.scale.toFixed(2) + "×"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                    }
                                }
                            }

                            Text {
                                text: "POSITION"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.letterSpacing: 2
                            }

                            Row {
                                width: parent.width
                                height: 34
                                spacing: 8

                                Rectangle {
                                    width: 150
                                    height: 32
                                    radius: Theme.radius
                                    color: Theme.bgPanel
                                    border.width: 1
                                    border.color: xInput.activeFocus
                                        ? Theme.accent
                                        : Theme.borderAccent

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "X"
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                    }

                                    TextInput {
                                        id: xInput
                                        anchors.left: parent.left
                                        anchors.leftMargin: 30
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(page.draftX)
                                        color: Theme.text
                                        selectionColor: Theme.accent
                                        selectedTextColor: Theme.bgPanel
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        validator: IntValidator {
                                            bottom: -32768
                                            top: 32768
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 150
                                    height: 32
                                    radius: Theme.radius
                                    color: Theme.bgPanel
                                    border.width: 1
                                    border.color: yInput.activeFocus
                                        ? Theme.accent
                                        : Theme.borderAccent

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Y"
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                    }

                                    TextInput {
                                        id: yInput
                                        anchors.left: parent.left
                                        anchors.leftMargin: 30
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(page.draftY)
                                        color: Theme.text
                                        selectionColor: Theme.accent
                                        selectedTextColor: Theme.bgPanel
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        validator: IntValidator {
                                            bottom: -32768
                                            top: 32768
                                        }
                                    }
                                }

                                Item {
                                    width: Math.max(0, parent.width - 410)
                                    height: 1
                                }

                                Rectangle {
                                    width: 94
                                    height: 32
                                    radius: Theme.radius
                                    color: positionMouse.containsMouse
                                        ? Theme.alpha(Theme.accent, 0.14)
                                        : Theme.bgPanel
                                    border.width: 1
                                    border.color: Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "APPLY POS"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                    }

                                    MouseArea {
                                        id: positionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: page.applyPosition(
                                            xInput.text,
                                            yInput.text
                                        )
                                    }
                                }
                            }

                            Text {
                                text: "Drag uses 10 px snapping and monitor-edge snapping. Manual X/Y is exact."
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                            }

                            Text {
                                text: "RESOLUTION"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.letterSpacing: 2
                            }

                            Flow {
                                id: resolutionFlow
                                width: parent.width
                                spacing: 7
                                height: childrenRect.height

                                Repeater {
                                    model: modelData.resolutions

                                    delegate: Rectangle {
                                        required property var modelData

                                        width: 104
                                        height: 32
                                        radius: Theme.radius
                                        color: (
                                            page.selectedWidth === modelData.width
                                            && page.selectedHeight === modelData.height
                                        )
                                            ? Theme.alpha(Theme.accent, 0.11)
                                            : Theme.bgPanel
                                        border.width: 1
                                        border.color: (
                                            page.selectedWidth === modelData.width
                                            && page.selectedHeight === modelData.height
                                        )
                                            ? Theme.accent
                                            : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.width + "×" + modelData.height
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 8
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: page.chooseResolution(
                                                modelData.width,
                                                modelData.height,
                                                modelData.refreshRates
                                            )
                                        }
                                    }
                                }
                            }

                            Text {
                                text: "REFRESH RATE"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.letterSpacing: 2
                            }

                            Flow {
                                id: refreshFlow
                                width: parent.width
                                spacing: 7
                                height: childrenRect.height

                                Repeater {
                                    model: {
                                        var mon = page.currentMonitor()
                                        var res = page.currentResolutionObject()
                                        return (
                                            mon && mon.name === modelData.name && res
                                        )
                                            ? res.refreshRates
                                            : []
                                    }

                                    delegate: Rectangle {
                                        required property var modelData

                                        width: 82
                                        height: 32
                                        radius: Theme.radius
                                        color: Math.abs(
                                            page.selectedRefresh - modelData
                                        ) < 0.05
                                            ? Theme.alpha(Theme.accent, 0.11)
                                            : Theme.bgPanel
                                        border.width: 1
                                        border.color: Math.abs(
                                            page.selectedRefresh - modelData
                                        ) < 0.05
                                            ? Theme.accent
                                            : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: Number(modelData).toFixed(2) + " Hz"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 8
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.selectedRefresh = Number(modelData)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 34
                                radius: Theme.radius
                                color: modeApplyMouse.containsMouse
                                    ? Theme.alpha(Theme.accent, 0.10)
                                    : Theme.bgPanel
                                border.width: 1
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "APPLY RESOLUTION + REFRESH RATE"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    id: modeApplyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.applySelectedMode()
                                }
                            }

                            Slider {
                                width: parent.width
                                label: "SCALE  " + modelData.scale.toFixed(2) + "×"
                                icon: "\uf00e"
                                value: (modelData.scale - 0.5) / 1.5

                                onCommitted: function(v) {
                                    page.applyScale(0.5 + v * 1.5)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "GLOBAL DISPLAY TOOLS"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Rectangle {
                width: parent.width
                height: 162
                radius: Theme.radius
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Slider {
                        width: parent.width
                        label: "BRIGHTNESS  "
                            + Math.round(page.brightnessValue * 100) + "%"
                        icon: "\uf185"
                        value: page.brightnessValue
                        accentColor: Theme.accent2

                        onMoved: function(value) {
                            page.brightnessValue = value
                        }

                        onCommitted: function(value) {
                            page.brightnessValue = value
                            page.commitBrightness(value)
                        }
                    }

                    Item {
                        width: parent.width
                        height: 72

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 46
                            spacing: 14

                            Slider {
                                width: parent.width - 84
                                height: 46
                                label: "NIGHT LIGHT"
                                icon: "\uf186"
                                value: page.nightlightValue
                                accentColor: Theme.accent

                                onMoved: function(value) {
                                    page.nightlightValue = value
                                }

                                onCommitted: function(value) {
                                    page.commitNightlight(value)
                                }
                            }

                            Rectangle {
                                width: 70
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.radius
                                color: page.nightlightEnabled
                                    ? Theme.alpha(Theme.accent, 0.10)
                                    : Theme.bgPanel
                                border.width: 1
                                border.color: page.nightlightEnabled
                                    ? Theme.accent
                                    : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: page.nightlightEnabled ? "ON" : "OFF"
                                    color: page.nightlightEnabled
                                        ? Theme.accent
                                        : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        if (page.nightlightEnabled)
                                            page.nightlightOff()
                                        else
                                            page.nightlightOn()
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 22
                            anchors.bottom: parent.bottom
                            text: page.nightlightTemperature(
                                page.nightlightValue
                            ) + " K"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: "WARMER  ←  →  COOLER"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                        }
                    }
                }
            }

            Item { width: 1; height: 10 }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: 3
            height: parent.height
            radius: 2
            color: Theme.alpha(Theme.border, 0.30)
            visible: contentArea.contentHeight > contentArea.height

            Rectangle {
                width: parent.width
                radius: 2
                color: Theme.accent
                opacity: 0.60
                height: Math.max(
                    24,
                    parent.height * contentArea.visibleArea.heightRatio
                )
                y: Math.min(
                    parent.height - height,
                    parent.height * contentArea.visibleArea.yPosition
                )
            }
        }
    }
}

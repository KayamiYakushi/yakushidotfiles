import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    readonly property string homeDir: Quickshell.env("HOME") || ""
    property real launcherOpacity: 0.8
    property string launcherStatus: ""

    property var presets: [
        { name: "MONO",    accent: "#ffffff" },
        { name: "RED",     accent: "#ff003c" },
        { name: "SAKURA",  accent: "#ff7a9d" },
        { name: "AMBER",   accent: "#ffb000" },
        { name: "MATCHA",  accent: "#9ccc65" },
        { name: "MINT",    accent: "#3ee6b5" },
        { name: "CYAN",    accent: "#00d4ff" },
        { name: "OCEAN",   accent: "#4d8dff" },
        { name: "VIOLET",  accent: "#9d7bff" },
        { name: "ORCHID",  accent: "#e070ff" }
    ]

    function launcherHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-appearancectl.py"
    }

    function loadLauncherOpacity() {
        if (homeDir === "" || launcherGet.running)
            return

        launcherGet.command = [
            "python3",
            launcherHelperPath(),
            "get"
        ]
        launcherGet.running = true
    }

    function saveLauncherOpacity(value) {
        if (launcherSet.running)
            return

        launcherSet.command = [
            "python3",
            launcherHelperPath(),
            "set",
            value.toFixed(3)
        ]
        launcherSet.running = true
    }

    // first load
    Component.onCompleted: {
        page.loadLauncherOpacity()
        page.loadWindow()
        termGet.command = ["python3", page.termHelperPath(), "status"]
        termGet.running = true
    }

    Process {
        id: launcherGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.launcherOpacity = data.opacity
                        page.launcherStatus = ""
                    } else {
                        page.launcherStatus = data.message
                    }
                } catch (e) {
                    page.launcherStatus = "Could not read app launcher opacity."
                }
            }
        }
    }

    Process {
        id: launcherSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.launcherOpacity = data.opacity
                        page.launcherStatus = data.message
                    } else {
                        page.launcherStatus = data.message
                    }
                } catch (e) {
                    page.launcherStatus = "Could not save app launcher opacity."
                }
            }
        }
    }

    Timer {
        id: launcherSaveDebounce
        interval: 120
        repeat: false
        onTriggered: page.saveLauncherOpacity(page.launcherOpacity)
    }

    // ------------------------------------------------------------------
    // Windows: gaps and corners (yakushi-windowctl.py)
    // ------------------------------------------------------------------
    property bool windowLoaded: false
    property int gapsOut: 3
    property int gapsIn: 3
    property int rounding: 8
    property int lastRadius: 8
    property bool shadow: true
    property int shadowSize: 8
    property bool border: false
    property int borderSize: 2
    property string borderColor: "accent"
    property string windowStatus: ""
    property var windowQueue: []

    function windowHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-windowctl.py"
    }

    function loadWindow() {
        windowGet.command = ["python3", windowHelperPath(), "get"]
        windowGet.running = true
    }

    function sendWindow(key, value) {
        windowQueue = windowQueue.filter(function(item) { return item[0] !== key })
        windowQueue.push([key, String(value)])
        pumpWindow()
    }

    function pumpWindow() {
        if (windowSet.running || windowQueue.length === 0 || homeDir === "")
            return
        var next = windowQueue.shift()
        windowSet.command = ["python3", windowHelperPath(), "set", next[0], next[1]]
        windowSet.running = true
    }

    function setRounding(value) {
        rounding = value
        if (value > 0)
            lastRadius = value
        sendWindow("rounding", value)
    }

    Process {
        id: windowGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok) {
                        page.gapsOut = data.gaps_out
                        page.gapsIn = data.gaps_in
                        page.rounding = data.rounding
                        if (data.rounding > 0)
                            page.lastRadius = data.rounding
                        page.shadow = data.shadow === true
                        page.shadowSize = data.shadow_size || 8
                        page.border = data.border === true
                        page.borderSize = data.border_size || 2
                        page.borderColor = data.border_color || "accent"
                        page.windowLoaded = true
                    } else {
                        page.windowStatus = data.message
                    }
                } catch (e) {
                    page.windowStatus = "Could not read window settings."
                }
            }
        }
    }

    Process {
        id: windowSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.windowStatus = data.ok ? "" : data.message
                } catch (e) {
                    page.windowStatus = "Could not save window settings."
                }
            }
        }

        onRunningChanged: if (!running) page.pumpWindow()
    }

    // ------------------------------------------------------------------
    // Terminal colours (yakushi-termctl.py)
    // ------------------------------------------------------------------
    property bool termEnabled: false
    property bool termLoaded: false
    property string termDetected: ""
    property string termStatus: ""
    property real termOpacity: 1.0
    property bool termBlur: true
    property int termBlurStrength: 3
    property string termName: ""
    property bool termColours: true

    function readTermSettings(data) {
        if (typeof data.opacity === "number")
            page.termOpacity = data.opacity
        if (typeof data.blur === "boolean")
            page.termBlur = data.blur
        if (typeof data.blurStrength === "number")
            page.termBlurStrength = data.blurStrength
    }

    function setTermBlur(on) {
        if (termBlurProc.running || homeDir === "")
            return
        termBlur = on
        termBlurProc.command = ["python3", termHelperPath(), "blur", on ? "on" : "off"]
        termBlurProc.running = true
    }

    function saveTermBlurStrength() {
        if (homeDir === "")
            return
        if (termStrengthProc.running) {
            termStrengthDebounce.restart()
            return
        }
        termStrengthProc.command = ["python3", termHelperPath(), "blur-strength", String(termBlurStrength)]
        termStrengthProc.running = true
    }

    Timer {
        id: termStrengthDebounce
        interval: 200
        onTriggered: page.saveTermBlurStrength()
    }

    Process {
        id: termBlurProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.readTermSettings(data)
                    page.termStatus = data.message || ""
                } catch (e) {
                    page.termStatus = "Could not change terminal blur."
                }
            }
        }
    }

    Process {
        id: termStrengthProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.termStatus = JSON.parse(text).message || ""
                } catch (e) {
                }
            }
        }
    }

    function saveTermOpacity() {
        if (homeDir === "")
            return
        if (termOpacityProc.running) {
            termOpacityDebounce.restart()
            return
        }
        termOpacityProc.command = ["python3", termHelperPath(), "opacity", termOpacity.toFixed(2)]
        termOpacityProc.running = true
    }

    Timer {
        id: termOpacityDebounce
        interval: 200
        onTriggered: page.saveTermOpacity()
    }

    Process {
        id: termOpacityProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termStatus = data.message || ""
                } catch (e) {
                }
            }
        }
    }

    function termHelperPath() {
        return homeDir + "/.config/quickshell/scripts/yakushi-termctl.py"
    }

    function describeTerm(data) {
        var parts = []
        var term = data.terminal || ""
        termName = term
        termColours = data.terminalColours !== false
        if (term !== "")
            parts.push(term + " (default" + (termColours ? "" : ", blur + opacity only") + ")")
        var others = (data.terminals || []).filter(function(t) { return t !== term })
        if (others.length > 0)
            parts.push(others.join(", "))
        if (data.fish)
            parts.push(data.shell === "fish" ? "fish (login shell)" : "fish")
        termDetected = parts.length > 0
            ? "Detected: " + parts.join("  ·  ")
            : "No supported terminal found (kitty, alacritty, foot, ghostty) and no fish."
    }

    function setTerm(on) {
        if (termSet.running || homeDir === "")
            return
        termEnabled = on
        termStatus = on ? "Applying colours..." : "Restoring colours..."
        termSet.command = ["python3", termHelperPath(), on ? "enable" : "disable"]
        termSet.running = true
    }

    Process {
        id: termGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termEnabled = data.enabled === true
                    page.readTermSettings(data)
                    page.describeTerm(data)
                    page.termLoaded = true
                } catch (e) {
                    page.termDetected = "Could not detect the terminal."
                }
            }
        }
    }

    Process {
        id: termSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termEnabled = data.enabled === true
                    page.readTermSettings(data)
                    page.termStatus = data.message || ""
                    page.describeTerm(data)
                } catch (e) {
                    page.termStatus = "Could not change terminal colours."
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Accent
    // ------------------------------------------------------------------
    function hexOf(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    function applyCustom(raw) {
        var value = raw.trim()
        if (value.charAt(0) !== "#")
            value = "#" + value
        if (/^#[0-9a-fA-F]{6}$/.test(value)) {
            Theme.accent = value.toLowerCase()
            return true
        }
        return false
    }

    component SectionLabel: Text {
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.line
    }

    ScrollHint {
        flick: flick
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: flick.width
            spacing: 18

            PageTitle {
                width: parent.width
                title: "APPEARANCE"
            }

            Divider {}

            // ---------------- Style: sharp / rounded ----------------
            SectionLabel { text: "STYLE" }

            Row {
                id: styleRow

                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        { key: "sharp", label: "SHARP", jp: "角", hint: "Hard corners, ruled lines" },
                        { key: "rounded", label: "ROUNDED", jp: "丸", hint: "Soft cards, the earlier look" }
                    ]

                    delegate: Rectangle {
                        id: styleCard

                        required property var modelData
                        readonly property bool rounded: modelData.key === "rounded"
                        readonly property bool selected: Theme.rounded === rounded

                        width: (styleRow.width - styleRow.spacing) / 2
                        height: 64
                        radius: Theme.corner
                        color: selected ? Theme.tint(Theme.accent, 0.10) : Theme.card
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (styleMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        // little window preview in that style
                        Rectangle {
                            id: preview

                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 54
                            height: 38
                            radius: styleCard.rounded ? 8 : 0
                            color: Theme.tint(Theme.ink, 0.04)
                            border.width: 1
                            border.color: styleCard.selected ? Theme.accent : Theme.inkMute

                            Rectangle {
                                x: 5
                                y: 5
                                width: 14
                                height: parent.height - 10
                                radius: styleCard.rounded ? 3 : 0
                                color: Theme.tint(Theme.ink, 0.10)
                            }

                            Rectangle {
                                x: 23
                                y: 7
                                width: 24
                                height: 4
                                radius: styleCard.rounded ? 2 : 0
                                color: styleCard.selected ? Theme.accent : Theme.inkSoft
                            }

                            Rectangle {
                                x: 23
                                y: 16
                                width: 24
                                height: 14
                                radius: styleCard.rounded ? 3 : 0
                                color: Theme.tint(Theme.ink, 0.10)
                            }
                        }

                        Column {
                            anchors.left: preview.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Row {
                                spacing: 8

                                Text {
                                    text: styleCard.modelData.label
                                    color: styleCard.selected ? Theme.accent : Theme.ink
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.letterSpacing: 2
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: styleCard.modelData.jp
                                    color: Theme.inkSoft
                                    font.family: "Noto Sans CJK JP"
                                    font.pixelSize: 11
                                }
                            }

                            Text {
                                width: parent.width
                                text: styleCard.modelData.hint
                                color: Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: styleMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.rounded = styleCard.rounded
                        }
                    }
                }
            }

            Divider {}

            SectionLabel { text: "ACCENT" }

            Grid {
                id: presetGrid

                width: parent.width
                columns: 5
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: page.presets

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: Qt.colorEqual(Theme.accent, modelData.accent)

                        width: (presetGrid.width - 4 * presetGrid.columnSpacing) / 5
                        height: 40
                        radius: Theme.corner
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? modelData.accent
                            : (presetMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 12
                                height: 12
                                radius: Theme.rounded ? (6) : 0
                                color: modelData.accent
                                border.width: 1
                                border.color: Theme.inkSoft
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.name
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: presetMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.accent = modelData.accent
                        }
                    }
                }
            }

            // Custom colour: any #rrggbb
            Item {
                width: parent.width
                height: 30

                Text {
                    id: customIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF03D8)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    anchors.left: customIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Custom colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Rectangle {
                    id: hexField

                    property bool invalid: false

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 132
                    height: 26
                    radius: Theme.corner
                    color: Theme.groove
                    border.width: 1
                    border.color: invalid
                        ? Theme.alert
                        : (hexInput.activeFocus ? Theme.accent : Theme.line)

                    Rectangle {
                        id: swatch

                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: Theme.rounded ? (6) : 0
                        color: Theme.accent
                    }

                    TextInput {
                        id: hexInput

                        anchors.left: swatch.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.hexOf(Theme.accent)
                        maximumLength: 7
                        color: Theme.ink
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        selectByMouse: true

                        onTextEdited: hexField.invalid = false

                        onAccepted: {
                            hexField.invalid = !page.applyCustom(text)
                            if (!hexField.invalid)
                                focus = false
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus) {
                                hexField.invalid = false
                                text = Qt.binding(function() { return page.hexOf(Theme.accent) })
                            }
                        }
                    }
                }
            }

            Divider {}

            SectionLabel { text: "GLASS" }

            Slider {
                width: parent.width
                label: "PANEL OPACITY  "
                    + Math.round(Theme.glass * 100)
                    + "%"
                icon: "◐"
                tint: Theme.accent
                value: (Theme.glass - 0.40) / 0.60

                onSliding: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }

                onSettled: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }
            }

            Slider {
                width: parent.width
                label: "App launcher opacity  "
                    + Math.round(page.launcherOpacity * 100)
                    + "%"
                icon: "󰀻"
                tint: Theme.accent
                value: page.launcherOpacity

                onSliding: function(v) {
                    page.launcherOpacity = v
                    launcherSaveDebounce.restart()
                }

                onSettled: function(v) {
                    page.launcherOpacity = v
                    launcherSaveDebounce.stop()
                    page.saveLauncherOpacity(v)
                }
            }

            Divider {}

            // ---------------- Windows ----------------
            SectionLabel { text: "WINDOWS" }

            Slider {
                width: parent.width
                opacity: page.windowLoaded ? 1 : 0.35
                label: "Screen edge gap  " + page.gapsOut + "px"
                icon: String.fromCodePoint(0xF00CE)
                tint: Theme.accent
                value: page.gapsOut / 30

                onSliding: function(v) {
                    var next = Math.round(v * 30)
                    if (next !== page.gapsOut) {
                        page.gapsOut = next
                        page.sendWindow("gaps_out", next)
                    }
                }

                onSettled: function(v) {
                    page.gapsOut = Math.round(v * 30)
                    page.sendWindow("gaps_out", page.gapsOut)
                }
            }

            Slider {
                width: parent.width
                opacity: page.windowLoaded ? 1 : 0.35
                label: "Gap between windows  " + page.gapsIn + "px"
                icon: String.fromCodePoint(0xF00D2)
                tint: Theme.accent
                value: page.gapsIn / 20

                onSliding: function(v) {
                    var next = Math.round(v * 20)
                    if (next !== page.gapsIn) {
                        page.gapsIn = next
                        page.sendWindow("gaps_in", next)
                    }
                }

                onSettled: function(v) {
                    page.gapsIn = Math.round(v * 20)
                    page.sendWindow("gaps_in", page.gapsIn)
                }
            }

            // Corners: rounded or sharp
            Row {
                width: parent.width
                spacing: 12
                opacity: page.windowLoaded ? 1 : 0.35

                Repeater {
                    model: [
                        { key: "rounded", name: "ROUNDED" },
                        { key: "sharp", name: "SHARP" }
                    ]

                    delegate: Rectangle {
                        id: cornerCard

                        required property var modelData
                        readonly property bool selected: modelData.key === "sharp"
                            ? page.rounding === 0
                            : page.rounding > 0

                        width: (body.width - 12) / 2
                        height: 48
                        radius: Theme.corner
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (cornerMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            // Tiny window showing the corner style
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 18
                                radius: cornerCard.modelData.key === "sharp" ? 0 : 5
                                color: "transparent"
                                border.width: 1.5
                                border.color: cornerCard.selected ? Theme.accent : Theme.inkSoft
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cornerCard.modelData.name
                                color: cornerCard.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }
                        }

                        MouseArea {
                            id: cornerMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.windowLoaded
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (cornerCard.selected)
                                    return
                                page.setRounding(cornerCard.modelData.key === "sharp" ? 0 : page.lastRadius)
                            }
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                visible: page.rounding > 0
                label: "Corner radius  " + page.rounding + "px"
                icon: String.fromCodePoint(0xF0607)
                tint: Theme.accent
                value: (page.rounding - 1) / 19

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 19)
                    if (next !== page.rounding)
                        page.setRounding(next)
                }

                onSettled: function(v) {
                    page.setRounding(1 + Math.round(v * 19))
                }
            }

            // ---------------- Shadow ----------------
            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF0637)
                label: "Window shadow"
                checked: page.shadow
                available: page.windowLoaded

                onToggled: {
                    page.shadow = !page.shadow
                    page.sendWindow("shadow", page.shadow ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.shadow
                label: "Shadow size  " + page.shadowSize + "px"
                icon: String.fromCodePoint(0xF1854)
                tint: Theme.accent
                value: (page.shadowSize - 2) / 38

                onSliding: function(v) {
                    var next = 2 + Math.round(v * 38)
                    if (next !== page.shadowSize) {
                        page.shadowSize = next
                        page.sendWindow("shadow_size", next)
                    }
                }

                onSettled: function(v) {
                    page.shadowSize = 2 + Math.round(v * 38)
                    page.sendWindow("shadow_size", page.shadowSize)
                }
            }

            // ---------------- Border ----------------
            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF00C9)
                label: "Window border"
                checked: page.border
                available: page.windowLoaded

                onToggled: {
                    page.border = !page.border
                    page.sendWindow("border", page.border ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.border
                label: "Border width  " + page.borderSize + "px"
                icon: String.fromCodePoint(0xF08A1)
                tint: Theme.accent
                value: (page.borderSize - 1) / 5

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 5)
                    if (next !== page.borderSize) {
                        page.borderSize = next
                        page.sendWindow("border_size", next)
                    }
                }

                onSettled: function(v) {
                    page.borderSize = 1 + Math.round(v * 5)
                    page.sendWindow("border_size", page.borderSize)
                }
            }

            // Border colour: follow the accent, or any #rrggbb
            Item {
                width: parent.width
                height: 30
                visible: page.border

                Text {
                    id: borderColourIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF0266)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    anchors.left: borderColourIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Border colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        readonly property bool selected: page.borderColor === "accent"

                        width: accentLabel.implicitWidth + 34
                        height: 26
                        radius: Theme.corner
                        color: selected ? Theme.tint(Theme.accent, 0.16) : "transparent"
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (accentMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                radius: Theme.rounded ? (5) : 0
                                color: Theme.accent
                            }

                            Text {
                                id: accentLabel

                                anchors.verticalCenter: parent.verticalCenter
                                text: "ACCENT"
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }

                        MouseArea {
                            id: accentMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                page.borderColor = "accent"
                                page.sendWindow("border_color", "accent")
                            }
                        }
                    }

                    Rectangle {
                        id: borderHexField

                        readonly property bool selected: page.borderColor !== "accent"
                        property bool invalid: false

                        width: 132
                        height: 26
                        radius: Theme.corner
                        color: Theme.groove
                        border.width: 1
                        border.color: invalid
                            ? Theme.alert
                            : (borderHexInput.activeFocus || selected ? Theme.accent : Theme.line)

                        Rectangle {
                            id: borderSwatch

                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: Theme.rounded ? (6) : 0
                            color: page.borderColor === "accent" ? Theme.inkMute : page.borderColor
                        }

                        TextInput {
                            id: borderHexInput

                            anchors.left: borderSwatch.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.borderColor === "accent" ? "" : page.borderColor
                            maximumLength: 7
                            color: Theme.ink
                            selectionColor: Theme.tint(Theme.accent, 0.4)
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            selectByMouse: true

                            Text {
                                visible: borderHexInput.text === "" && !borderHexInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#rrggbb"
                                color: Theme.inkMute
                                font: borderHexInput.font
                            }

                            onTextEdited: borderHexField.invalid = false

                            onAccepted: {
                                var value = text.trim()
                                if (value.charAt(0) !== "#")
                                    value = "#" + value
                                if (/^#[0-9a-fA-F]{6}$/.test(value)) {
                                    page.borderColor = value.toLowerCase()
                                    page.sendWindow("border_color", page.borderColor)
                                    focus = false
                                } else {
                                    borderHexField.invalid = true
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Shadows cost a little GPU time; turn them off for the lightest setup."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Divider {}

            // ---------------- Terminal ----------------
            SectionLabel { text: "TERMINAL" }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF018D)
                label: "Match terminal colours"
                checked: page.termEnabled
                available: page.termLoaded && !termSet.running
                onToggled: page.setTerm(!page.termEnabled)
            }

            Slider {
                width: parent.width
                visible: page.termEnabled
                label: "Terminal opacity  " + Math.round(page.termOpacity * 100) + "%"
                icon: "◐"
                tint: Theme.accent
                value: (page.termOpacity - 0.30) / 0.70

                onSliding: function(v) {
                    page.termOpacity = 0.30 + v * 0.70
                    termOpacityDebounce.restart()
                }

                onSettled: function(v) {
                    page.termOpacity = 0.30 + v * 0.70
                    termOpacityDebounce.stop()
                    page.saveTermOpacity()
                }
            }

            ToggleRow {
                width: parent.width
                visible: page.termEnabled
                icon: String.fromCodePoint(0xF00B5)
                label: "Background blur"
                checked: page.termBlur
                available: !termBlurProc.running
                onToggled: page.setTermBlur(!page.termBlur)
            }

            Slider {
                width: parent.width
                visible: page.termEnabled && page.termBlur
                label: "Blur strength  " + page.termBlurStrength
                icon: "≋"
                tint: Theme.accent
                value: (page.termBlurStrength - 1) / 9

                onSliding: function(v) {
                    page.termBlurStrength = Math.round(1 + v * 9)
                    termStrengthDebounce.restart()
                }

                onSettled: function(v) {
                    page.termBlurStrength = Math.round(1 + v * 9)
                    termStrengthDebounce.stop()
                    page.saveTermBlurStrength()
                }
            }

            Text {
                width: parent.width
                text: page.termDetected
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: page.termStatus !== ""
                    ? page.termStatus
                    : "Background, palette, cursor and selection follow the accent; with fish, command colours do too. Blur is done by Hyprland, so it works with any terminal, and shows when opacity is below 100% (strength also applies to the launcher). The first time, open a new terminal window. Off restores everything."
                wrapMode: Text.WordWrap
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                visible: page.launcherStatus !== "" || page.windowStatus !== ""
                width: parent.width
                text: page.windowStatus !== "" ? page.windowStatus : page.launcherStatus
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}

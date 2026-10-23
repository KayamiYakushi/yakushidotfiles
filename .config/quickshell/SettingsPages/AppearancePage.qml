import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    property string homeDir: ""
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

    Process {
        id: homeProc
        command: ["sh", "-c", "printf '%s' \"$HOME\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.homeDir = text.trim()
                page.loadLauncherOpacity()
                page.loadWindow()
            }
        }
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
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.border
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

            Text {
                text: "APPEARANCE"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.letterSpacing: 3
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
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: selected
                            ? modelData.accent
                            : (presetMouse.containsMouse ? Theme.borderAccent : Theme.border)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                color: modelData.accent
                                border.width: 1
                                border.color: Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.name
                                color: parent.parent.selected ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
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
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                }

                Text {
                    anchors.left: customIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Custom colour"
                    color: Theme.text
                    font.family: Theme.fontFamily
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
                    radius: Theme.radius
                    color: Theme.trackBg
                    border.width: 1
                    border.color: invalid
                        ? Theme.danger
                        : (hexInput.activeFocus ? Theme.accent : Theme.border)

                    Rectangle {
                        id: swatch

                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
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
                        color: Theme.text
                        selectionColor: Theme.alpha(Theme.accent, 0.4)
                        font.family: Theme.fontFamily
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
                    + Math.round(Theme.panelOpacity * 100)
                    + "%"
                icon: "◐"
                accentColor: Theme.accent
                value: (Theme.panelOpacity - 0.40) / 0.60

                onMoved: function(v) {
                    Theme.panelOpacity = 0.40 + (v * 0.60)
                }

                onCommitted: function(v) {
                    Theme.panelOpacity = 0.40 + (v * 0.60)
                }
            }

            Slider {
                width: parent.width
                label: "App launcher opacity  "
                    + Math.round(page.launcherOpacity * 100)
                    + "%"
                icon: "󰀻"
                accentColor: Theme.accent
                value: page.launcherOpacity

                onMoved: function(v) {
                    page.launcherOpacity = v
                    launcherSaveDebounce.restart()
                }

                onCommitted: function(v) {
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
                accentColor: Theme.accent
                value: page.gapsOut / 30

                onMoved: function(v) {
                    var next = Math.round(v * 30)
                    if (next !== page.gapsOut) {
                        page.gapsOut = next
                        page.sendWindow("gaps_out", next)
                    }
                }

                onCommitted: function(v) {
                    page.gapsOut = Math.round(v * 30)
                    page.sendWindow("gaps_out", page.gapsOut)
                }
            }

            Slider {
                width: parent.width
                opacity: page.windowLoaded ? 1 : 0.35
                label: "Gap between windows  " + page.gapsIn + "px"
                icon: String.fromCodePoint(0xF00D2)
                accentColor: Theme.accent
                value: page.gapsIn / 20

                onMoved: function(v) {
                    var next = Math.round(v * 20)
                    if (next !== page.gapsIn) {
                        page.gapsIn = next
                        page.sendWindow("gaps_in", next)
                    }
                }

                onCommitted: function(v) {
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
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (cornerMouse.containsMouse ? Theme.borderAccent : Theme.border)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.animFast }
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
                                border.color: cornerCard.selected ? Theme.accent : Theme.textDim
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cornerCard.modelData.name
                                color: cornerCard.selected ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
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
                accentColor: Theme.accent
                value: (page.rounding - 1) / 19

                onMoved: function(v) {
                    var next = 1 + Math.round(v * 19)
                    if (next !== page.rounding)
                        page.setRounding(next)
                }

                onCommitted: function(v) {
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
                accentColor: Theme.accent
                value: (page.shadowSize - 2) / 38

                onMoved: function(v) {
                    var next = 2 + Math.round(v * 38)
                    if (next !== page.shadowSize) {
                        page.shadowSize = next
                        page.sendWindow("shadow_size", next)
                    }
                }

                onCommitted: function(v) {
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
                accentColor: Theme.accent
                value: (page.borderSize - 1) / 5

                onMoved: function(v) {
                    var next = 1 + Math.round(v * 5)
                    if (next !== page.borderSize) {
                        page.borderSize = next
                        page.sendWindow("border_size", next)
                    }
                }

                onCommitted: function(v) {
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
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                }

                Text {
                    anchors.left: borderColourIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Border colour"
                    color: Theme.text
                    font.family: Theme.fontFamily
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
                        radius: Theme.radius
                        color: selected ? Theme.alpha(Theme.accent, 0.16) : "transparent"
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (accentMouse.containsMouse ? Theme.borderAccent : Theme.border)

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                radius: 5
                                color: Theme.accent
                            }

                            Text {
                                id: accentLabel

                                anchors.verticalCenter: parent.verticalCenter
                                text: "ACCENT"
                                color: parent.parent.selected ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
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
                        radius: Theme.radius
                        color: Theme.trackBg
                        border.width: 1
                        border.color: invalid
                            ? Theme.danger
                            : (borderHexInput.activeFocus || selected ? Theme.accent : Theme.border)

                        Rectangle {
                            id: borderSwatch

                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: page.borderColor === "accent" ? Theme.textFaint : page.borderColor
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
                            color: Theme.text
                            selectionColor: Theme.alpha(Theme.accent, 0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            selectByMouse: true

                            Text {
                                visible: borderHexInput.text === "" && !borderHexInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#rrggbb"
                                color: Theme.textFaint
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
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                visible: page.launcherStatus !== "" || page.windowStatus !== ""
                width: parent.width
                text: page.windowStatus !== "" ? page.windowStatus : page.launcherStatus
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}

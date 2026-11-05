import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property var hostWindow: null
    clip: true

    readonly property string homeDir: Quickshell.env("HOME") || ""
    property string currentLayout: ""
    property real currentSensitivity: 0.0
    property string statusText: "Loading input settings..."
    property bool statusError: false

    function helperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-inputctl.py"
    }

    function refreshState() {
        if (homeDir === "" || getProc.running)
            return

        getProc.command = ["python3", helperPath(), "get"]
        getProc.running = true
    }

    function refreshLayouts() {
        if (homeDir === "" || layoutsProc.running)
            return

        layoutsProc.command = ["python3", helperPath(), "layouts"]
        layoutsProc.running = true
    }

    function layoutMatches(name, code) {
        var q = layoutSearch.text.trim().toLowerCase()

        if (q === "")
            return true

        return name.toLowerCase().indexOf(q) !== -1
            || code.toLowerCase().indexOf(q) !== -1
    }

    function setLayout(code) {
        if (layoutProc.running)
            return

        statusText = "Applying " + code.toUpperCase() + "..."
        statusError = false

        layoutProc.command = [
            "python3",
            helperPath(),
            "set-layout",
            code
        ]
        layoutProc.running = true
    }

    ListModel {
        id: layoutsModel
    }

    // ---- mouse cursor themes (scripts/yakushi-cursorctl.py)
    readonly property string cursorHelper: homeDir + "/.config/quickshell/scripts/yakushi-cursorctl.py"
    property var cursorThemes: []
    property string cursorTheme: ""
    property string cursorNote: ""
    property int cursorSize: 24
    property bool cursorShake: false
    property real cursorHold: 0.35          // seconds it stays big after the shaking stops
    readonly property real holdMin: 0.1
    readonly property real holdMax: 3.0

    // slider position <-> seconds; squared so short times get more room
    function holdToSlider(sec) {
        return Math.sqrt(Math.max(0, (sec - holdMin) / (holdMax - holdMin)))
    }

    function sliderToHold(v) {
        return Math.round((holdMin + (holdMax - holdMin) * v * v) * 10) / 10
    }

    function setCursorHold(sec) {
        cursorHold = sec
        holdSave.restart()
    }

    // save once the slider rests (a busy helper just means: try again shortly)
    Timer {
        id: holdSave

        interval: 250
        onTriggered: {
            if (!page.cursorCall(["hold", page.cursorHold.toFixed(1)]))
                restart()
        }
    }
    readonly property var cursorSizes: [16, 20, 24, 32, 40, 48, 64]

    function cursorCall(args) {
        if (cursorJob.running)
            return false
        cursorJob.command = ["python3", cursorHelper].concat(args)
        cursorJob.running = true
        return true
    }

    function setCursorTheme(id) {
        if (id !== cursorTheme && cursorCall(["set", id]))
            cursorTheme = id
    }

    function setCursorSize(px) {
        if (px !== cursorSize && cursorCall(["size", String(px)]))
            cursorSize = px
    }

    function setCursorShake(on) {
        if (cursorCall(["shake", on ? "on" : "off"]))
            cursorShake = on
    }

    Process {
        id: cursorJob

        command: ["python3", page.cursorHelper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.themes)
                        page.cursorThemes = d.themes
                    if (d.current)
                        page.cursorTheme = d.current
                    if (d.size)
                        page.cursorSize = d.size
                    if (d.shake !== undefined)
                        page.cursorShake = d.shake
                    if (d.hold !== undefined && !holdSave.running)
                        page.cursorHold = d.hold
                    page.cursorNote = d.message || ""
                } catch (e) {
                    page.cursorNote = "Could not read the cursor themes."
                }
            }
        }
    }

    // first load
    Component.onCompleted: {
        page.refreshState()
        page.refreshLayouts()
        cursorJob.running = true
    }

    Process {
        id: getProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (!data.ok) {
                        page.statusText = data.message
                        page.statusError = true
                        return
                    }

                    page.currentLayout = data.layout
                    page.currentSensitivity = data.sensitivity
                    page.statusText = "Input settings loaded."
                    page.statusError = false
                } catch (e) {
                    page.statusText = "Could not read input settings."
                    page.statusError = true
                }
            }
        }
    }

    Process {
        id: layoutsProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    layoutsModel.clear()

                    for (var i = 0; i < data.length; ++i) {
                        layoutsModel.append({
                            code: data[i].code,
                            name: data[i].name
                        })
                    }
                } catch (e) {
                    page.statusText = "Could not load XKB layout catalog."
                    page.statusError = true
                }
            }
        }
    }

    Process {
        id: layoutProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.statusText = data.message
                    page.statusError = !data.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }

                page.refreshState()
            }
        }
    }

    Process {
        id: runtimeProc

        stdout: StdioCollector {
            onStreamFinished: {}
        }
    }

    Process {
        id: persistProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.statusText = data.message
                    page.statusError = !data.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }

                page.refreshState()
            }
        }
    }

    Process {
        id: restoreProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.statusText = data.message
                    page.statusError = !data.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }

                page.refreshState()
            }
        }
    }

    Timer {
        id: sensitivityDebounce
        interval: 45
        repeat: false

        onTriggered: {
            if (runtimeProc.running)
                return

            runtimeProc.command = [
                "python3",
                page.helperPath(),
                "runtime-sensitivity",
                page.currentSensitivity.toFixed(3)
            ]
            runtimeProc.running = true
        }
    }

    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30

        PageTitle {
            anchors.left: parent.left
            anchors.right: titleActions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "INPUT"
        }

        Row {
            id: titleActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            HeaderButton {
                label: "UNDO LAST"
                icon: String.fromCodePoint(0xF054C)

                onActivated: {
                    if (restoreProc.running)
                        return
                    restoreProc.command = ["python3", page.helperPath(), "restore"]
                    restoreProc.running = true
                }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Text {
        id: statusLine
        textFormat: Text.PlainText
        anchors.top: divider.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16
        text: page.statusText
        color: page.statusError ? Theme.alert : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Text {
        id: languageTitle
        textFormat: Text.PlainText
        anchors.top: statusLine.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        text: "KEYBOARD LANGUAGE"
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Rectangle {
        id: layoutSearchBox
        anchors.top: languageTitle.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 38
        color: Theme.card
        border.width: 1
        border.color: layoutSearch.activeFocus
            ? Theme.accent
            : Theme.line

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: layoutSearch.activeFocus ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 14
        }

        Text {
            textFormat: Text.PlainText
            visible: layoutSearch.text === ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 36
            text: "Search keyboard layouts (e.g. turkish, tr, german)..."
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
        }

        TextInput {
            id: layoutSearch
            anchors.fill: parent
            anchors.leftMargin: 36
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            selectionColor: Theme.tint(Theme.accent, 0.45)
            font.family: Theme.mono
            font.pixelSize: 10
            clip: true
        }
    }

    ScrollHint {
        flick: layoutList
    }

    ListView {
        id: layoutList
        anchors.top: layoutSearchBox.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: pointerDivider.top
        anchors.bottomMargin: 14
        clip: true
        // Rows carry their own gap: hidden (filtered-out) rows must take no
        // space at all, and ListView spacing would still add up between them.
        spacing: 0
        model: layoutsModel
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 200

        delegate: Item {
            id: layoutRow

            required property string code
            required property string name
            readonly property bool current: page.currentLayout.split(",").indexOf(code) !== -1

            width: ListView.view.width
            height: visible ? 44 : 0
            visible: page.layoutMatches(name, code)

            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: 6
                color: layoutRow.current
                    ? Theme.tint(Theme.accent, 0.13)
                    : rowMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : Theme.card
                border.width: 1
                border.color: layoutRow.current
                    ? Theme.accent
                    : rowMouse.containsMouse ? Theme.lineHot : Theme.line

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: codeBadge.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: layoutRow.name
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: codeBadge

                    anchors.right: stateIcon.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: codeText.implicitWidth + 14
                    height: 22
                    color: Theme.tint(Theme.ink, 0.06)

                    Text {
                        id: codeText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: layoutRow.code.toUpperCase()
                        color: layoutRow.current ? Theme.accent : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }

                Text {
                    id: stateIcon

                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    horizontalAlignment: Text.AlignHCenter
                    text: layoutRow.current ? String.fromCodePoint(0xF012C) : ""
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 15
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!layoutRow.current) page.setLayout(layoutRow.code)
                }
            }
        }
    }

    Rectangle {
        id: pointerDivider
        anchors.bottom: pointerTitle.top
        anchors.bottomMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Text {
        id: pointerTitle
        textFormat: Text.PlainText
        anchors.bottom: pointerSlider.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        text: "POINTER"
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Slider {
        id: pointerSlider
        anchors.bottom: pointerScale.top
        anchors.bottomMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right

        label: "POINTER SPEED  "
            + (page.currentSensitivity >= 0 ? "+" : "")
            + page.currentSensitivity.toFixed(2)

        icon: "󰍽"
        tint: Theme.accent
        value: (page.currentSensitivity + 1.0) / 2.0

        onSliding: function(v) {
            page.currentSensitivity = -1.0 + (v * 2.0)
            sensitivityDebounce.restart()
        }

        onSettled: function(v) {
            page.currentSensitivity = -1.0 + (v * 2.0)

            if (persistProc.running)
                return

            persistProc.command = [
                "python3",
                page.helperPath(),
                "set-sensitivity",
                page.currentSensitivity.toFixed(2)
            ]
            persistProc.running = true
        }
    }

    Row {
        id: pointerScale
        anchors.bottom: cursorDivider.top
        anchors.bottomMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right

        Text {
            textFormat: Text.PlainText
            text: "-1.00  SLOW"
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
        }

        Item {
            width: Math.max(0, parent.width - 190)
            height: 1
        }

        Text {
            textFormat: Text.PlainText
            text: "FAST  +1.00"
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
        }
    }

    // ---------------- Cursor ----------------
    Rectangle {
        id: cursorDivider
        anchors.bottom: cursorTitle.top
        anchors.bottomMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Text {
        id: cursorTitle
        textFormat: Text.PlainText
        anchors.bottom: cursorStrip.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        text: "CURSOR"
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.baseline: cursorTitle.baseline
        anchors.left: cursorTitle.right
        anchors.leftMargin: 16
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: page.cursorNote !== "" ? page.cursorNote
            : page.cursorThemes.length + " installed  ·  click one to use it"
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 9
    }

    // one row of tiles; a Row (not a ListView) so the scroll range is exact
    // and the last tile always fits in whole
    Flickable {
        id: cursorStrip

        readonly property real maxX: Math.max(0, contentWidth - width)

        function scrollTo(x) {
            contentX = Math.round(Math.min(maxX, Math.max(0, x)))
        }

        anchors.bottom: cursorControls.top
        anchors.bottomMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 84
        contentWidth: cursorRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        clip: true

        // new list or narrower window: stay inside the range
        onMaxXChanged: if (contentX > maxX) scrollTo(contentX)
        // the wheel (up/down or sideways) moves the row, a tile per notch
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => cursorStrip.scrollTo(cursorStrip.contentX - event.angleDelta.y)
        }
        WheelHandler {
            orientation: Qt.Horizontal
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => cursorStrip.scrollTo(cursorStrip.contentX - event.angleDelta.x)
        }

        Row {
            id: cursorRow

            spacing: 8

            Repeater {
                model: page.cursorThemes

                delegate: Rectangle {
                    id: cursorTile

                    required property var modelData
                    readonly property bool current: page.cursorTheme === modelData.id

                    width: 112
                    height: 84
                    color: current ? Theme.tint(Theme.accent, 0.13)
                        : tileMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : Theme.card
                    border.width: 1
                    border.color: current ? Theme.accent
                        : tileMouse.containsMouse ? Theme.lineHot : Theme.line

                    Behavior on color {
                        ColorAnimation { duration: Theme.tFast }
                    }

                    // the theme's arrow on a mid-grey patch, so dark and light cursors both show
                    Rectangle {
                        id: patch

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        width: 44
                        height: 44
                        color: "#5a5f6a"

                        Image {
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            source: cursorTile.modelData.preview ? "file://" + cursorTile.modelData.preview : ""
                            sourceSize.width: 32
                            sourceSize.height: 32
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            cache: false
                            asynchronous: true
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: !cursorTile.modelData.preview
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF01BF)
                            color: Theme.ink
                            font.family: Theme.glyphs
                            font.pixelSize: 20
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.top: patch.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 14
                        horizontalAlignment: Text.AlignHCenter
                        text: cursorTile.modelData.name
                        elide: Text.ElideRight
                        color: cursorTile.current ? Theme.accent : Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }

                    // marks the one that comes with Yakushi
                    Text {
                        textFormat: Text.PlainText
                        visible: cursorTile.modelData.yakushi === true
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 5
                        text: "薬"
                        color: Theme.accent
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: tileMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.setCursorTheme(cursorTile.modelData.id)
                    }
                }
            }
        }
    }

    // size chips on the left, shake to find on the right
    Column {
        id: cursorControls

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        Item {
            width: parent.width
            height: 26

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 4
                    text: "SIZE"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                Repeater {
                    model: page.cursorSizes

                    delegate: Rectangle {
                        id: sizeChip

                        required property int modelData
                        readonly property bool current: page.cursorSize === modelData

                        width: 34
                        height: 24
                        color: current ? Theme.tint(Theme.accent, 0.16)
                            : sizeMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : Theme.card
                        border.width: 1
                        border.color: current ? Theme.accent
                            : sizeMouse.containsMouse ? Theme.lineHot : Theme.line

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: sizeChip.modelData
                            color: sizeChip.current ? Theme.ink : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: sizeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setCursorSize(sizeChip.modelData)
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SHAKE TO FIND"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.cursorShake
                    available: !cursorJob.running
                    onToggled: page.setCursorShake(!page.cursorShake)
                }
            }
        }

        // how long the big cursor stays after the shaking stops
        Item {
            visible: page.cursorShake
            width: parent.width
            height: visible ? 22 : 0

            Text {
                id: holdLabel

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                text: "STAYS BIG"
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                font.letterSpacing: 2
            }

            Text {
                id: holdShort

                textFormat: Text.PlainText
                anchors.left: holdLabel.right
                anchors.verticalCenter: parent.verticalCenter
                text: "SHORT"
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 8
                font.letterSpacing: 1
            }

            LineSlider {
                anchors.left: holdShort.right
                anchors.leftMargin: 12
                anchors.right: holdLong.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                value: page.holdToSlider(page.cursorHold)
                onSliding: function(v) { page.setCursorHold(page.sliderToHold(v)) }
                onSettled: function(v) { page.setCursorHold(page.sliderToHold(v)) }
            }

            Text {
                id: holdLong

                textFormat: Text.PlainText
                anchors.right: holdValue.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "LONG"
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 8
                font.letterSpacing: 1
            }

            Text {
                id: holdValue

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                horizontalAlignment: Text.AlignRight
                text: page.cursorHold.toFixed(1) + " s"
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }
}

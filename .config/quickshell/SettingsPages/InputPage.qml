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

    // first load
    Component.onCompleted: {
        page.refreshState()
        page.refreshLayouts()
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
        radius: Theme.rounded ? (10) : 0
        color: Theme.card
        border.width: 1
        border.color: layoutSearch.activeFocus
            ? Theme.accent
            : Theme.line

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: layoutSearch.activeFocus ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 14
        }

        Text {
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
        height: 236
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
                radius: Theme.rounded ? (10) : 0
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
                    radius: Theme.rounded ? (11) : 0
                    color: Theme.tint(Theme.ink, 0.06)

                    Text {
                        id: codeText

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
        anchors.top: layoutList.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Text {
        id: pointerTitle
        anchors.top: pointerDivider.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        text: "POINTER"
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Slider {
        id: pointerSlider
        anchors.top: pointerTitle.bottom
        anchors.topMargin: 8
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
        anchors.top: pointerSlider.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right

        Text {
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
            text: "FAST  +1.00"
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
        }
    }
}

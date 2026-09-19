import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page
    clip: true

    property string homeDir: ""
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

    Process {
        id: homeProc
        command: ["sh", "-c", "printf '%s' \"$HOME\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.homeDir = text.trim()
                page.refreshState()
                page.refreshLayouts()
            }
        }
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

    Row {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30

        Text {
            text: "INPUT"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.letterSpacing: 3
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: Math.max(0, parent.width - 198)
            height: 1
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
        id: divider
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.border
    }

    Text {
        id: statusLine
        anchors.top: divider.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16
        text: page.statusText
        color: page.statusError ? Theme.danger : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Text {
        id: languageTitle
        anchors.top: statusLine.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        text: "KEYBOARD LANGUAGE"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Rectangle {
        id: layoutSearchBox
        anchors.top: languageTitle.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        radius: Theme.radius
        color: Theme.bgCard
        border.width: 1
        border.color: layoutSearch.activeFocus
            ? Theme.accent
            : Theme.border

        Text {
            visible: layoutSearch.text === ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 11
            text: "Search all installed XKB layouts..."
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        TextInput {
            id: layoutSearch
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.bgPanel
            font.family: Theme.fontFamily
            font.pixelSize: 9
            clip: true
        }
    }

    ListView {
        id: layoutList
        anchors.top: layoutSearchBox.bottom
        anchors.topMargin: 7
        anchors.left: parent.left
        anchors.right: parent.right
        height: 220
        clip: true
        spacing: 4
        model: layoutsModel
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            required property string code
            required property string name

            width: ListView.view.width - 7
            height: visible ? 38 : 0
            visible: page.layoutMatches(name, code)
            radius: Theme.radius
            color: page.currentLayout.split(",").indexOf(code) !== -1
                ? Theme.alpha(Theme.accent, 0.11)
                : Theme.bgCard
            border.width: 1
            border.color: page.currentLayout.split(",").indexOf(code) !== -1
                ? Theme.accent
                : Theme.border

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                text: name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                anchors.right: applyLayout.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: code.toUpperCase()
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                id: applyLayout
                width: 58
                height: 26
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: applyMouse.containsMouse
                    ? Theme.alpha(Theme.accent, 0.12)
                    : Theme.bgPanel
                border.width: 1
                border.color: Theme.borderAccent

                Text {
                    anchors.centerIn: parent
                    text: "APPLY"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 7
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: applyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setLayout(code)
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
        color: Theme.border
    }

    Text {
        id: pointerTitle
        anchors.top: pointerDivider.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        text: "POINTER"
        color: Theme.textDim
        font.family: Theme.fontFamily
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
        accentColor: Theme.accent
        value: (page.currentSensitivity + 1.0) / 2.0

        onMoved: function(v) {
            page.currentSensitivity = -1.0 + (v * 2.0)
            sensitivityDebounce.restart()
        }

        onCommitted: function(v) {
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
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 8
        }

        Item {
            width: Math.max(0, parent.width - 190)
            height: 1
        }

        Text {
            text: "FAST  +1.00"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 8
        }
    }
}

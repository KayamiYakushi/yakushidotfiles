import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page

    property var hostWindow: null
    clip: true

    property string homeDir: ""
    property string statusText: "Loading keybinds..."
    property bool statusError: false
    property var allBinds: []

    function helperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-keybindctl.py"
    }

    function refresh() {
        if (homeDir === "" || listProc.running)
            return

        listProc.command = ["python3", helperPath(), "list"]
        listProc.running = true
    }

    function applyBinding(bindId, combo) {
        if (setProc.running)
            return

        statusText = "Applying " + combo + "..."
        statusError = false

        setProc.command = [
            "python3",
            helperPath(),
            "set",
            bindId,
            combo
        ]
        setProc.running = true
    }

    function setBindingEnabled(bindId, wanted) {
        if (toggleProc.running)
            return

        statusText = wanted ? "Enabling shortcut..." : "Disabling shortcut..."
        statusError = false

        toggleProc.command = [
            "python3",
            helperPath(),
            wanted ? "enable" : "disable",
            bindId
        ]
        toggleProc.running = true
    }

    function rebuildFiltered() {
        var q = searchInput.text.trim().toLowerCase()
        bindsModel.clear()

        for (var i = 0; i < allBinds.length; ++i) {
            var b = allBinds[i]
            var matched = q === ""
                || b.label.toLowerCase().indexOf(q) !== -1
                || b.category.toLowerCase().indexOf(q) !== -1
                || b.combo.toLowerCase().indexOf(q) !== -1

            if (matched) {
                bindsModel.append({
                    bindId: b.id,
                    category: b.category,
                    label: b.label,
                    combo: b.combo,
                    danger: b.danger,
                    bindEnabled: b.bindEnabled
                })
            }
        }

        bindList.positionViewAtBeginning()
    }

    ListModel {
        id: bindsModel
    }

    Process {
        id: homeProc
        command: ["sh", "-c", "printf '%s' \"$HOME\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.homeDir = text.trim()
                page.refresh()
            }
        }
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.allBinds = data
                    page.rebuildFiltered()
                    page.statusText = data.length + " keybinds loaded."
                    page.statusError = false
                } catch (e) {
                    page.statusText = "Could not parse keybind list."
                    page.statusError = true
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim() === ""
                        ? "Keybind update failed."
                        : text.trim()
                    page.statusError = true
                }

                page.refresh()
            }
        }
    }

    Process {
        id: toggleProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim() === ""
                        ? "Keybind toggle failed."
                        : text.trim()
                    page.statusError = true
                }

                page.refresh()
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

                page.refresh()
            }
        }
    }

    Row {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30
        spacing: 8

        Text {
            text: "KEYBINDS"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.letterSpacing: 3
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: Math.max(0, parent.width - 356)
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
        id: divider
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.border
    }

    Rectangle {
        id: searchBox
        anchors.top: divider.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        radius: Theme.radius
        color: Theme.bgCard
        border.width: 1
        border.color: searchInput.activeFocus
            ? Theme.accent
            : Theme.border

        Text {
            visible: searchInput.text === ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            text: "Search actions, categories or shortcuts..."
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.bgPanel
            font.family: Theme.fontFamily
            font.pixelSize: 10
            clip: true

            onTextChanged: page.rebuildFiltered()
        }
    }

    Text {
        id: statusLine
        anchors.top: searchBox.bottom
        anchors.topMargin: 8
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
        id: helpLine
        anchors.top: statusLine.bottom
        anchors.topMargin: 3
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16
        text: "Read-only by default. EDIT changes a shortcut; OFF disables it without deleting."
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    ListView {
        id: bindList
        anchors.top: helpLine.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 5
        model: bindsModel
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000
        cacheBuffer: 250

        delegate: Rectangle {
            id: bindRow

            required property string bindId
            required property string category
            required property string label
            required property string combo
            required property bool danger
            required property bool bindEnabled

            property bool editing: false

            width: ListView.view.width - 8
            height: 54
            clip: true

            radius: Theme.radius
            color: Theme.bgCard
            opacity: bindEnabled ? 1.0 : 0.55
            border.width: 1
            border.color: danger
                ? Theme.alpha(Theme.danger, 0.50)
                : Theme.border

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: comboBox.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: bindRow.label
                    color: bindRow.danger ? Theme.danger : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    text: bindRow.category.toUpperCase()
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 7
                    font.letterSpacing: 1
                }
            }

            Rectangle {
                id: comboBox
                width: Math.min(200, Math.max(130, bindRow.width * 0.31))
                height: 30
                anchors.right: toggleButton.left
                anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: Theme.bgPanel
                border.width: 1
                border.color: comboInput.activeFocus
                    ? Theme.accent
                    : Theme.borderAccent

                TextInput {
                    id: comboInput
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    text: bindRow.combo
                    readOnly: !bindRow.editing
                    color: bindRow.bindEnabled ? Theme.text : Theme.textDim
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bgPanel
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    clip: true

                    onAccepted: {
                        if (!bindRow.editing)
                            return

                        page.applyBinding(bindRow.bindId, text)
                        bindRow.editing = false
                    }

                    Keys.onEscapePressed: {
                        text = bindRow.combo
                        bindRow.editing = false
                        focus = false
                    }
                }
            }

            Rectangle {
                id: toggleButton
                width: 56
                height: 30
                anchors.right: editButton.left
                anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: toggleMouse.containsMouse
                    ? Theme.alpha(
                        bindRow.bindEnabled ? Theme.danger : Theme.ok,
                        0.12
                    )
                    : Theme.bgPanel
                border.width: 1
                border.color: bindRow.bindEnabled
                    ? Theme.alpha(Theme.ok, 0.65)
                    : Theme.alpha(Theme.danger, 0.65)

                Text {
                    anchors.centerIn: parent
                    text: bindRow.bindEnabled ? "ON" : "OFF"
                    color: bindRow.bindEnabled ? Theme.ok : Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: toggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: page.setBindingEnabled(
                        bindRow.bindId,
                        !bindRow.bindEnabled
                    )
                }
            }

            Rectangle {
                id: editButton
                width: 58
                height: 30
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: editMouse.containsMouse
                    ? Theme.alpha(Theme.accent, 0.12)
                    : Theme.bgPanel
                border.width: 1
                border.color: bindRow.editing
                    ? Theme.accent
                    : Theme.borderAccent

                Text {
                    anchors.centerIn: parent
                    text: bindRow.editing ? "SAVE" : "EDIT"
                    color: bindRow.editing ? Theme.accent : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: editMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (!bindRow.editing) {
                            bindRow.editing = true
                            comboInput.forceActiveFocus()
                            comboInput.selectAll()
                            return
                        }

                        page.applyBinding(
                            bindRow.bindId,
                            comboInput.text
                        )
                        bindRow.editing = false
                    }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: 3
            height: parent.height
            radius: 2
            color: Theme.alpha(Theme.border, 0.30)
            visible: bindList.contentHeight > bindList.height

            Rectangle {
                width: parent.width
                radius: 2
                color: Theme.accent
                opacity: 0.60
                height: Math.max(
                    24,
                    parent.height * bindList.visibleArea.heightRatio
                )
                y: Math.min(
                    parent.height - height,
                    parent.height * bindList.visibleArea.yPosition
                )
            }
        }
    }
}

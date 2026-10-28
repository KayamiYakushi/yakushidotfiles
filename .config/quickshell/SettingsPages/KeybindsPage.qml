import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property var hostWindow: null
    clip: true

    readonly property string homeDir: Quickshell.env("HOME") || ""
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

    // first load
    Component.onCompleted: {
        page.refresh()
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
            title: "KEYBINDS"
        }

        Row {
            id: titleActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            HeaderButton {
                label: "RELOAD"
                icon: String.fromCodePoint(0xF0450)
                onActivated: page.refresh()
            }

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

    Rectangle {
        id: searchBox
        anchors.top: divider.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 38
        radius: Theme.rounded ? (10) : 0
        color: Theme.card
        border.width: 1
        border.color: searchInput.activeFocus
            ? Theme.accent
            : Theme.line

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: searchInput.activeFocus ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 14
        }

        Text {
            visible: searchInput.text === ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 36
            text: "Search actions, categories or shortcuts..."
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
        }

        TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: 36
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            selectionColor: Theme.accent
            selectedTextColor: Theme.surface
            font.family: Theme.mono
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
        color: page.statusError ? Theme.alert : Theme.inkSoft
        font.family: Theme.mono
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
        text: "The pencil edits a shortcut (Enter saves, Esc cancels); the switch turns one off without deleting it."
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    ScrollHint {
        flick: bindList
    }

    ListView {
        id: bindList
        anchors.top: helpLine.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 6
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
            readonly property var keys: combo.split("+").map(function(k) { return k.trim() })
                .filter(function(k) { return k !== "" })

            width: ListView.view.width
            height: 50
            radius: Theme.rounded ? (10) : 0
            color: rowHover.hovered || editing ? Theme.tint(Theme.ink, 0.035) : Theme.card
            border.width: 1
            border.color: editing
                ? Theme.accent
                : danger ? Theme.tint(Theme.alert, 0.45)
                : rowHover.hovered ? Theme.lineHot : Theme.line

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }

            HoverHandler {
                id: rowHover
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: keyArea.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                opacity: bindRow.bindEnabled ? 1.0 : 0.45

                Text {
                    width: parent.width
                    text: bindRow.label
                    color: bindRow.danger ? Theme.alert : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    text: bindRow.category.toUpperCase()
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
            }

            // Keycaps (or the editor while editing)
            Item {
                id: keyArea

                anchors.right: enableSwitch.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: bindRow.editing ? 210 : keycaps.implicitWidth
                height: 28
                opacity: bindRow.bindEnabled || bindRow.editing ? 1.0 : 0.45

                Row {
                    id: keycaps

                    visible: !bindRow.editing
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: bindRow.keys

                        delegate: Rectangle {
                            required property string modelData

                            width: Math.max(26, capText.implicitWidth + 14)
                            height: 24
                            radius: Theme.rounded ? (6) : 0
                            color: Theme.tint(Theme.ink, 0.06)
                            border.width: 1
                            border.color: Theme.tint(Theme.ink, 0.10)

                            // subtle key "depth"
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                height: 2
                                radius: Theme.rounded ? (1) : 0
                                color: Theme.tint("#000000", 0.35)
                            }

                            Text {
                                id: capText

                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                text: parent.modelData
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                Rectangle {
                    visible: bindRow.editing
                    anchors.fill: parent
                    radius: Theme.rounded ? (8) : 0
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.accent

                    TextInput {
                        id: comboInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: bindRow.combo
                        readOnly: !bindRow.editing
                        color: Theme.ink
                        selectionColor: Theme.tint(Theme.accent, 0.45)
                        font.family: Theme.mono
                        font.pixelSize: 10
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
            }

            Switch {
                id: enableSwitch

                anchors.right: editButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                checked: bindRow.bindEnabled
                onToggled: page.setBindingEnabled(bindRow.bindId, !bindRow.bindEnabled)
            }

            IconButton {
                id: editButton

                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                glyph: String.fromCodePoint(bindRow.editing ? 0xF012C : 0xF03EB)

                onActivated: {
                    if (!bindRow.editing) {
                        bindRow.editing = true
                        comboInput.forceActiveFocus()
                        comboInput.selectAll()
                        return
                    }

                    page.applyBinding(bindRow.bindId, comboInput.text)
                    bindRow.editing = false
                }
            }
        }
    }
}

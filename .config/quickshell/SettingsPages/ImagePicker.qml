import QtQuick
import Quickshell.Io
import "../"

// In-panel image picker.
//
// This lives INSIDE the Settings card instead of being a separate window, so it
// shares the same surface, animation language and keyboard focus as the rest of
// Settings. It is opened through SettingsWindow.openImagePicker(...).
Item {
    id: picker

    property string homeDir: ""
    property string currentDir: ""
    property string parentDir: ""
    property string selectedPath: ""
    property string searchText: ""
    property bool opened: false
    property bool refreshPending: false

    signal accepted(string path)
    signal closed()

    visible: opened || opacity > 0.01
    opacity: opened ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animMed
            easing.type: Easing.OutCubic
        }
    }

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------

    // Percent-encode every path segment so names containing '#', '%' or
    // spaces still resolve to the right file.
    function fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    function helperPath() {
        return homeDir + "/.config/quickshell/scripts/yakushi-image-picker.py"
    }

    function openAt(path) {
        currentDir = (path && path.length > 0) ? path : homeDir
        selectedPath = ""
        searchText = ""
        searchInput.text = ""
        opened = true
        runRefresh()
        searchInput.forceActiveFocus()
    }

    function dismiss() {
        if (!opened)
            return

        opened = false
        closed()
    }

    function accept() {
        if (selectedPath === "")
            return

        var chosen = selectedPath
        dismiss()
        accepted(chosen)
    }

    function runRefresh() {
        if (homeDir === "")
            return

        if (listProc.running) {
            refreshPending = true
            return
        }

        refreshPending = false
        listProc.command = ["python3", helperPath(), currentDir, searchText]
        listProc.running = true
    }

    function goTo(path) {
        if (!path || path.length === 0)
            return

        currentDir = path
        selectedPath = ""
        searchText = ""
        searchInput.text = ""
        runRefresh()
    }

    function goParent() {
        if (parentDir !== "" && parentDir !== currentDir)
            goTo(parentDir)
    }

    Keys.onEscapePressed: picker.dismiss()

    Timer {
        id: refreshDebounce
        interval: 180
        repeat: false
        onTriggered: picker.runRefresh()
    }

    ListModel {
        id: entriesModel
    }

    Process {
        id: listProc

        onRunningChanged: {
            if (!running && picker.refreshPending)
                picker.runRefresh()
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (!data.ok)
                        return

                    picker.currentDir = data.directory || picker.currentDir
                    picker.parentDir = data.parent || ""
                    resultCount.text = (data.count || 0) + (data.count === 1 ? " ITEM" : " ITEMS")

                    entriesModel.clear()

                    var rows = data.entries || []
                    for (var i = 0; i < rows.length; ++i)
                        entriesModel.append(rows[i])
                } catch (e) {
                    resultCount.text = "READ ERROR"
                }
            }
        }
    }

    // ------------------------------------------------------------
    // Reusable button
    // ------------------------------------------------------------

    component PickerButton: Rectangle {
        id: btn

        property string label: ""
        property bool primary: false
        property bool iconOnly: false

        signal clicked()

        radius: Theme.radius
        border.width: 1
        border.color: (primary && enabled) ? Theme.accent : Theme.border

        color: (primary && enabled)
            ? Theme.alpha(Theme.accent, btnMouse.containsMouse ? 0.18 : 0.10)
            : ((btnMouse.containsMouse && enabled)
                ? Theme.alpha(Theme.text, 0.06)
                : Theme.alpha(Theme.text, 0.0))

        opacity: enabled ? 1.0 : 0.5

        Behavior on color {
            ColorAnimation { duration: Theme.animFast }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.animFast }
        }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? Theme.text : Theme.textDim
            font.family: btn.iconOnly ? Theme.iconFont : Theme.fontFamily
            font.pixelSize: btn.iconOnly ? 14 : 10
            font.bold: btn.primary
            font.letterSpacing: btn.iconOnly ? 0 : 1
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: btn.clicked()
        }
    }

    // ------------------------------------------------------------
    // Scrim (click outside the panel to close)
    // ------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#a6000000"

        MouseArea {
            anchors.fill: parent
            onClicked: picker.dismiss()
        }
    }

    // ------------------------------------------------------------
    // Panel
    // ------------------------------------------------------------

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width - 56, 880)
        height: Math.min(parent.height - 56, 560)

        radius: Theme.radius + 2
        color: "#f5060606"
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.55)

        scale: picker.opened ? 1.0 : 0.96

        Behavior on scale {
            NumberAnimation {
                duration: Theme.animSlow
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            y: picker.opened ? 0 : 10

            Behavior on y {
                NumberAnimation {
                    duration: Theme.animSlow
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Swallow clicks inside the panel so they never reach the scrim.
        MouseArea {
            anchors.fill: parent
        }

        // ---------------- Header ----------------
        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            height: 32

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "CHOOSE IMAGE"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.letterSpacing: 3
            }

            PickerButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                iconOnly: true
                label: "\uf00d"
                onClicked: picker.dismiss()
            }
        }

        Rectangle {
            id: headerRule

            anchors.top: header.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            height: 1
            color: Theme.border
        }

        // ---------------- Places ----------------
        Column {
            id: places

            anchors.top: headerRule.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.leftMargin: 24
            width: 150
            spacing: 4

            Repeater {
                model: [
                    { name: "Home",      icon: "󰋜", path: picker.homeDir },
                    { name: "Documents", icon: "󰈙", path: picker.homeDir + "/Documents" },
                    { name: "Downloads", icon: "󰇚", path: picker.homeDir + "/Downloads" },
                    { name: "Pictures",  icon: "󰋩", path: picker.homeDir + "/Pictures" }
                ]

                delegate: Rectangle {
                    id: place

                    required property var modelData

                    readonly property bool active: picker.currentDir === modelData.path

                    width: places.width
                    height: 36
                    radius: Theme.radius

                    color: active
                        ? Theme.alpha(Theme.accent, 0.12)
                        : (placeMouse.containsMouse
                            ? Theme.alpha(Theme.text, 0.05)
                            : Theme.alpha(Theme.text, 0.0))

                    border.width: active ? 1 : 0
                    border.color: Theme.accent

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }

                    Rectangle {
                        visible: place.active
                        width: 3
                        height: parent.height - 10
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent2
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Text {
                            text: place.modelData.icon
                            color: place.active ? Theme.accent : Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                        }

                        Text {
                            text: place.modelData.name
                            color: place.active ? Theme.text : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: placeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.goTo(place.modelData.path)
                    }
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            text: "IMAGES ONLY"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 2
        }

        Rectangle {
            id: verticalRule

            anchors.top: headerRule.bottom
            anchors.topMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.left: places.right
            anchors.leftMargin: 20
            width: 1
            color: Theme.border
        }

        // ---------------- Main column ----------------
        Item {
            id: main

            anchors.top: headerRule.bottom
            anchors.topMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.left: verticalRule.right
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.rightMargin: 24

            // Toolbar
            Item {
                id: toolbar

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 38

                PickerButton {
                    id: backButton

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    iconOnly: true
                    label: "󰁍"
                    enabled: picker.parentDir !== "" && picker.parentDir !== picker.currentDir
                    onClicked: picker.goParent()
                }

                Rectangle {
                    id: searchField

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(230, Math.max(170, parent.width * 0.32))
                    height: 38
                    radius: Theme.radius
                    color: Theme.bgCard
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.accent : Theme.border

                    Behavior on border.color {
                        ColorAnimation { duration: Theme.animFast }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        color: searchInput.activeFocus ? Theme.accent : Theme.textDim
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                    }

                    TextInput {
                        id: searchInput

                        anchors.left: parent.left
                        anchors.leftMargin: 36
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter

                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.bgPanel
                        clip: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 11

                        onTextChanged: {
                            if (text === picker.searchText)
                                return

                            picker.searchText = text
                            refreshDebounce.restart()
                        }

                        Keys.onReturnPressed: picker.accept()
                        Keys.onEnterPressed: picker.accept()

                        Text {
                            visible: searchInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "SEARCH"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                    }
                }

                Rectangle {
                    anchors.left: backButton.right
                    anchors.leftMargin: 8
                    anchors.right: searchField.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 38
                    radius: Theme.radius
                    color: Theme.bgCard
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: picker.currentDir
                        color: Theme.textDim
                        elide: Text.ElideMiddle
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // Footer
            Item {
                id: footer

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 38

                Text {
                    id: resultCount

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "0 ITEMS"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                PickerButton {
                    id: openButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    height: 38
                    label: "OPEN"
                    primary: true
                    enabled: picker.selectedPath !== ""
                    onClicked: picker.accept()
                }

                PickerButton {
                    anchors.right: openButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 100
                    height: 38
                    label: "CANCEL"
                    onClicked: picker.dismiss()
                }
            }

            // List
            Rectangle {
                id: listFrame

                anchors.top: toolbar.bottom
                anchors.topMargin: 12
                anchors.bottom: footer.top
                anchors.bottomMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right

                radius: Theme.radius
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.border
                clip: true

                ListView {
                    id: resultList

                    anchors.fill: parent
                    anchors.margins: 8
                    model: entriesModel
                    spacing: 4
                    clip: true
                    cacheBuffer: 320
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row

                        required property string name
                        required property string path
                        required property bool is_dir
                        required property bool is_image

                        readonly property bool selected: picker.selectedPath === path

                        width: resultList.width - 8
                        height: 58
                        radius: Theme.radius

                        color: selected
                            ? Theme.alpha(Theme.accent, 0.12)
                            : (rowMouse.containsMouse
                                ? Theme.alpha(Theme.text, 0.05)
                                : Theme.alpha(Theme.text, 0.0))

                        border.width: selected ? 1 : 0
                        border.color: Theme.accent

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        Rectangle {
                            visible: row.selected
                            width: 3
                            height: parent.height - 10
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent2
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 6
                            anchors.leftMargin: 12
                            spacing: 12

                            Rectangle {
                                width: 46
                                height: 46
                                radius: Theme.radius
                                color: Theme.bgPanel
                                border.width: 1
                                border.color: Theme.border
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    visible: row.is_image
                                    source: row.is_image ? picker.fileUrl(row.path) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 96
                                    sourceSize.height: 96
                                    opacity: status === Image.Ready ? 1 : 0

                                    Behavior on opacity {
                                        NumberAnimation { duration: Theme.animMed }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: row.is_dir
                                    text: "󰉋"
                                    color: Theme.accent
                                    font.family: Theme.iconFont
                                    font.pixelSize: 20
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 60
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: row.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: row.is_dir ? "FOLDER" : "IMAGE"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    font.letterSpacing: 1
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            // Folders open on a single click; images are selected
                            // first and confirmed with OPEN / double-click / Enter.
                            onClicked: {
                                if (row.is_dir)
                                    picker.goTo(row.path)
                                else
                                    picker.selectedPath = row.path
                            }

                            onDoubleClicked: {
                                if (!row.is_dir) {
                                    picker.selectedPath = row.path
                                    picker.accept()
                                }
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: entriesModel.count === 0 && !listProc.running
                    text: picker.searchText !== ""
                        ? "NO MATCHING IMAGES"
                        : "NO IMAGES IN THIS FOLDER"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                // Slim scroll indicator
                Rectangle {
                    visible: resultList.contentHeight > resultList.height
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    width: 3
                    radius: 1.5
                    color: Theme.alpha(Theme.text, 0.25)

                    height: Math.max(
                        24,
                        (resultList.height / Math.max(1, resultList.contentHeight)) * (listFrame.height - 16)
                    )

                    y: 8 + (listFrame.height - 16 - height)
                        * Math.max(0, Math.min(1,
                            resultList.contentY
                            / Math.max(1, resultList.contentHeight - resultList.height)))
                }
            }
        }
    }
}

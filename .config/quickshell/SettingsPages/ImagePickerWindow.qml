import QtQuick
import QtQuick.Window
import Quickshell.Io
import "../"

Window {
    id: picker

    title: "Yakushi Image Picker"
    width: 980
    height: 640
    minimumWidth: 900
    minimumHeight: 580
    visible: false
    color: "transparent"
    flags: Qt.Dialog | Qt.FramelessWindowHint

    property string homeDir: ""
    property string currentDir: ""
    property string parentDir: ""
    property string selectedPath: ""
    property string selectedName: ""
    property string searchText: ""
    property bool refreshPending: false
    property var hostWindow: null

    signal accepted(string path)

    function helperPath() {
        return homeDir + "/.config/quickshell/scripts/yakushi-image-picker.py"
    }

    function openAt(path) {
        currentDir = path && path.length > 0 ? path : homeDir
        selectedPath = ""
        selectedName = ""
        searchText = ""
        searchInput.text = ""
        visible = true
        requestRefresh()
        raise()
        requestActivate()
        searchInput.forceActiveFocus()
    }

    function closePicker() {
        visible = false
    }

    function requestRefresh() {
        refreshDebounce.restart()
    }

    function runRefresh() {
        if (homeDir === "")
            return

        if (listProc.running) {
            refreshPending = true
            return
        }

        refreshPending = false

        listProc.command = [
            "python3",
            helperPath(),
            currentDir,
            searchText
        ]
        listProc.running = true
    }

    function goTo(path) {
        if (!path || path.length === 0)
            return

        currentDir = path
        selectedPath = ""
        selectedName = ""
        searchText = ""
        searchInput.text = ""
        requestRefresh()
    }

    function goParent() {
        if (parentDir !== "" && parentDir !== currentDir)
            goTo(parentDir)
    }

    onVisibleChanged: {
        if (!hostWindow)
            return

        if (visible)
            hostWindow.beginExternalDialog()
        else
            hostWindow.endExternalDialog()
    }

    onClosing: function(close) {
        close.accepted = false
        closePicker()
    }

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
                    resultCount.text = (data.count || 0) + " ITEMS"

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

    Rectangle {
        id: tiltBackdrop
        anchors.fill: parent
        color: Theme.bg
        radius: 6
    }

    Rectangle {
        id: card

        anchors.fill: parent

        // YAKUSHI_PICKER_TILT_BEGIN
        // Safe hover-only parallax: no wrapper component and no layout changes.
        property real parallaxX: 0
        property real parallaxY: 0
        property real tiltStrength: 4

        transform: [
            Rotation {
                origin.x: card.width / 2
                origin.y: card.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: card.parallaxX

                Behavior on angle {
                    NumberAnimation {
                        duration: Theme.animSlow
                        easing.type: Easing.OutCubic
                    }
                }
            },
            Rotation {
                origin.x: card.width / 2
                origin.y: card.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: card.parallaxY

                Behavior on angle {
                    NumberAnimation {
                        duration: Theme.animSlow
                        easing.type: Easing.OutCubic
                    }
                }
            }
        ]

        HoverHandler {
            id: pickerTiltHover

            onPointChanged: {
                if (card.width <= 0 || card.height <= 0)
                    return

                var nx = (point.position.x / card.width) - 0.5
                var ny = (point.position.y / card.height) - 0.5

                card.parallaxX = -ny * card.tiltStrength
                card.parallaxY = nx * card.tiltStrength
            }

            onHoveredChanged: {
                if (!hovered) {
                    card.parallaxX = 0
                    card.parallaxY = 0
                }
            }
        }
        // YAKUSHI_PICKER_TILT_END

        color: Theme.bg
        radius: 6
        border.color: Theme.accent
        border.width: 1

        Keys.onEscapePressed: picker.closePicker()
        focus: true

        Rectangle {
            width: 40
            height: 2
            color: Theme.accent2
            anchors {
                top: parent.top
                left: parent.left
                margins: 14
            }
        }

        Rectangle {
            width: 2
            height: 40
            color: Theme.accent2
            anchors {
                top: parent.top
                left: parent.left
                margins: 14
            }
        }

        Rectangle {
            width: 40
            height: 2
            color: Theme.accent2
            anchors {
                bottom: parent.bottom
                right: parent.right
                margins: 14
            }
        }

        Rectangle {
            width: 2
            height: 40
            color: Theme.accent2
            anchors {
                bottom: parent.bottom
                right: parent.right
                margins: 14
            }
        }

        Row {
            id: layoutRow
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            Column {
                id: sidebar

                width: 220
                height: parent.height
                spacing: 22

                Row {
                    width: parent.width
                    spacing: 12

                    Text {
                        text: "薬"
                        color: Theme.danger
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 30
                        font.bold: true
                    }

                    Column {
                        spacing: 2

                        Text {
                            text: "YAKUSHI"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                            font.letterSpacing: 4
                        }

                        Text {
                            text: "IMAGE PICKER"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: [
                            { name: "Home",      icon: "󰋜", path: picker.homeDir },
                            { name: "Documents", icon: "󰈙", path: picker.homeDir + "/Documents" },
                            { name: "Downloads", icon: "󰇚", path: picker.homeDir + "/Downloads" },
                            { name: "Pictures",  icon: "󰋩", path: picker.homeDir + "/Pictures" }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            width: sidebar.width
                            height: 38
                            radius: Theme.radius

                            property bool active:
                                picker.currentDir === modelData.path

                            color: active
                                ? Theme.alpha(Theme.accent, 0.12)
                                : "transparent"

                            border.width: active ? 1 : 0
                            border.color: Theme.accent

                            Rectangle {
                                visible: parent.active
                                width: 3
                                height: parent.height - 10
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                color: Theme.accent2
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                spacing: 12

                                Text {
                                    text: modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                    color: parent.parent.active
                                        ? Theme.accent
                                        : Theme.textDim
                                }

                                Text {
                                    text: modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: parent.parent.active
                                        ? Theme.text
                                        : Theme.textDim
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.goTo(modelData.path)
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: Math.max(0, parent.height - 280)
                }

                Text {
                    width: parent.width
                    text: "IMAGES ONLY"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            Rectangle {
                id: divider
                width: 1
                height: parent.height
                color: Theme.border
            }

            Column {
                width: layoutRow.width - sidebar.width - divider.width - (layoutRow.spacing * 2)
                height: parent.height
                spacing: 18

                Text {
                    text: "CHOOSE IMAGE"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.letterSpacing: 3
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                Row {
                    width: parent.width
                    height: 42
                    spacing: 10

                    Rectangle {
                        width: 42
                        height: 42
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "󰁍"
                            color: Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.goParent()
                        }
                    }

                    Rectangle {
                        width: parent.width - searchField.width - 52
                        height: 42
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

                    Rectangle {
                        id: searchField

                        width: Math.min(260, Math.max(220, parent.width * 0.30))
                        height: 42
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: searchInput.activeFocus
                            ? Theme.accent
                            : Theme.border

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter

                            text: "󰍉"
                            color: searchInput.activeFocus
                                ? Theme.accent
                                : Theme.textDim

                            font.family: Theme.iconFont
                            font.pixelSize: 13
                        }

                        TextInput {
                            id: searchInput

                            anchors.left: parent.left
                            anchors.leftMargin: 38
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
                                picker.searchText = text
                                picker.requestRefresh()
                            }

                            Text {
                                visible: searchInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter

                                text: "SEARCH IMAGES"
                                color: Theme.textFaint

                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 18 - 1 - 18 - 42 - 18 - 48 - 18
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

                        delegate: Rectangle {
                            required property string name
                            required property string path
                            required property bool is_dir
                            required property bool is_image

                            width: resultList.width
                            height: 66
                            radius: Theme.radius

                            property bool selected:
                                picker.selectedPath === path

                            color: selected
                                ? Theme.alpha(Theme.accent, 0.12)
                                : (rowMouse.containsMouse
                                    ? Theme.alpha(Theme.text, 0.04)
                                    : "transparent")

                            border.width: selected ? 1 : 0
                            border.color: Theme.accent

                            Rectangle {
                                visible: parent.selected
                                width: 3
                                height: parent.height - 10
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.accent2
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 6
                                anchors.leftMargin: 10
                                spacing: 12

                                Rectangle {
                                    width: 54
                                    height: 54
                                    radius: Theme.radius
                                    color: Theme.bgPanel
                                    border.width: 1
                                    border.color: Theme.border
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: is_image
                                        source: is_image
                                            ? "file://" + path
                                            : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: is_dir
                                        text: "󰉋"
                                        color: Theme.accent
                                        font.family: Theme.iconFont
                                        font.pixelSize: 20
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 70
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        text: name
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        text: is_dir ? "FOLDER" : "IMAGE"
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

                                onClicked: {
                                    if (is_dir) {
                                        picker.selectedPath = ""
                                        picker.selectedName = ""
                                    } else {
                                        picker.selectedPath = path
                                        picker.selectedName = name
                                    }
                                }

                                onDoubleClicked: {
                                    if (is_dir) {
                                        picker.goTo(path)
                                    } else {
                                        picker.accepted(path)
                                        picker.closePicker()
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 48
                    spacing: 10

                    Text {
                        id: resultCount
                        width: parent.width - 250
                        verticalAlignment: Text.AlignVCenter
                        text: "0 ITEMS"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }

                    Rectangle {
                        width: 110
                        height: 38
                        radius: Theme.radius
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.closePicker()
                        }
                    }

                    Rectangle {
                        width: 130
                        height: 38
                        radius: Theme.radius

                        color: picker.selectedPath !== ""
                            ? Theme.alpha(Theme.accent, 0.10)
                            : "transparent"

                        border.width: 1
                        border.color: picker.selectedPath !== ""
                            ? Theme.accent
                            : Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "OPEN"

                            color: picker.selectedPath !== ""
                                ? Theme.text
                                : Theme.textFaint

                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: picker.selectedPath !== ""
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: picker.selectedPath !== ""
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                picker.accepted(picker.selectedPath)
                                picker.closePicker()
                            }
                        }
                    }
                }
            }
        }
    }
}

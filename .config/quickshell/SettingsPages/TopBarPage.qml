import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Top Bar
//
// Chooses the bar (Island or Waybar), which island modules are shown, the
// clock format and the bar opacity. Every change is saved by
// scripts/yakushi-topbarctl.py and applied to the running bar at once.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: (Quickshell.env("HOME") || "")
        + "/.config/quickshell/scripts/yakushi-topbarctl.py"

    property bool loaded: false
    property string style: "island"
    property bool seconds: true
    property bool clock24: true
    property real barOpacity: 0.90
    property var modules: ({})
    property string visualizer: "hover"
    readonly property var defaultOrder: [
        "workspaces", "ram", "cpu", "cpuTemp", "gpuTemp",
        "date", "time", "media", "volume", "power"
    ]
    property string status: ""

    readonly property bool island: style === "island"

    function glyph(code) {
        return String.fromCodePoint(code)
    }

    function infoFor(key) {
        for (var i = 0; i < moduleItems.length; i++)
            if (moduleItems[i].key === key)
                return moduleItems[i]
        return { key: key, label: key, icon: "" }
    }

    function fillOrder(list) {
        orderModel.clear()
        for (var i = 0; i < list.length; i++)
            orderModel.append({ key: list[i] })
    }

    function currentOrder() {
        var list = []
        for (var i = 0; i < orderModel.count; i++)
            list.push(orderModel.get(i).key)
        return list
    }

    function moveModule(from, to) {
        if (to < 0 || to >= orderModel.count || from === to)
            return
        orderModel.move(from, to, 1)
        send("order", currentOrder().join(","))
    }

    function resetOrder() {
        fillOrder(defaultOrder)
        send("order", "default")
    }

    ListModel {
        id: orderModel
    }

    readonly property var moduleItems: [
        { key: "workspaces", label: "Workspaces",   icon: glyph(0xF056E) },
        { key: "ram",        label: "RAM usage",    icon: glyph(0xF035B) },
        { key: "cpu",        label: "CPU usage",    icon: glyph(0xF0EE0) },
        { key: "cpuTemp",    label: "CPU temp",     icon: glyph(0xF050F) },
        { key: "gpuTemp",    label: "GPU temp",     icon: glyph(0xF08AE) },
        { key: "media",      label: "Now playing",  icon: glyph(0xF0387) },
        { key: "volume",     label: "Volume",       icon: glyph(0xF057E) },
        { key: "date",       label: "Date",         icon: glyph(0xF00ED) },
        { key: "time",       label: "Time",         icon: glyph(0xF0150) },
        { key: "power",      label: "Power",        icon: glyph(0xF0425) }
    ]

    // ------------------------------------------------------------------
    // Backend: one helper call at a time, queued so fast clicks never race.
    // ------------------------------------------------------------------
    property var queue: []

    function applyState(data) {
        if (data.style === "island" || data.style === "waybar")
            style = data.style
        if (typeof data.seconds === "boolean")
            seconds = data.seconds
        if (typeof data.clock24 === "boolean")
            clock24 = data.clock24
        if (typeof data.opacity === "number")
            barOpacity = data.opacity
        if (data.modules)
            modules = data.modules
        if (typeof data.visualizer === "string")
            visualizer = data.visualizer
        if (orderModel.count === 0)
            fillOrder(Array.isArray(data.order) ? data.order : defaultOrder)
        loaded = true
    }

    function send(key, value) {
        // Drop an older queued value for the same key (e.g. slider drags).
        queue = queue.filter(function(item) { return item[0] !== key })
        queue.push([key, value])
        pump()
    }

    function pump() {
        if (setProc.running || queue.length === 0)
            return

        var next = queue.shift()
        setProc.command = ["python3", helper, "set", next[0], next[1]]
        setProc.running = true
    }

    function setModule(key, on) {
        var next = {}
        for (var k in modules)
            next[k] = modules[k]
        next[key] = on
        modules = next
        send("module." + key, on ? "on" : "off")
    }

    Process {
        id: getProc

        running: true
        command: ["python3", page.helper, "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok)
                        page.applyState(data)
                    else
                        page.status = data.message || ""
                } catch (e) {
                    page.status = "Could not read top bar settings."
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.status = data.message || ""
                    // Opacity is the only value the user may still be
                    // dragging, so it is never pulled back from a reply.
                    if (!data.ok)
                        getProc.running = true
                } catch (e) {
                    page.status = "Could not save top bar settings."
                }
            }
        }

        onRunningChanged: {
            if (!running)
                page.pump()
        }
    }

    Timer {
        id: opacityDebounce
        interval: 150
        repeat: false
        onTriggered: page.send("opacity", page.barOpacity.toFixed(3))
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
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
            spacing: 16

            Text {
                text: "TOP BAR"
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

            // ---------------- Style ----------------
            Text {
                text: "STYLE"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                spacing: 12

                Repeater {
                    model: [
                        { key: "island", name: "ISLAND", note: "Notch hanging from the top edge" },
                        { key: "waybar", name: "WAYBAR", note: "Classic three-section bar" }
                    ]

                    delegate: Rectangle {
                        id: card

                        required property var modelData
                        readonly property bool selected: page.style === modelData.key

                        width: (body.width - 12) / 2
                        height: 76
                        radius: Theme.radius
                        color: Theme.bgCard
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (cardMouse.containsMouse ? Theme.borderAccent : Theme.border)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        // Miniature of the bar
                        Item {
                            id: preview

                            anchors.top: parent.top
                            anchors.topMargin: 12
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 32
                            height: 14

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: Theme.trackBg
                            }

                            // Island: one notch in the middle
                            Rectangle {
                                visible: card.modelData.key === "island"
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                width: parent.width * 0.46
                                height: 10
                                bottomLeftRadius: 5
                                bottomRightRadius: 5
                                color: card.selected ? Theme.accent : Theme.textFaint
                            }

                            // Waybar: three floating sections
                            Row {
                                visible: card.modelData.key === "waybar"
                                anchors.fill: parent
                                anchors.margins: 3
                                spacing: (width - 3 * (width * 0.24)) / 2

                                Repeater {
                                    model: 3

                                    Rectangle {
                                        width: preview.width * 0.24 - 2
                                        height: 8
                                        radius: 3
                                        color: card.selected ? Theme.accent : Theme.textFaint
                                    }
                                }
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            spacing: 3

                            Text {
                                text: card.modelData.name
                                color: card.selected ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }

                            Text {
                                width: parent.width
                                text: card.modelData.note
                                elide: Text.ElideRight
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: cardMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (card.selected)
                                    return
                                page.style = card.modelData.key
                                page.send("style", card.modelData.key)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---------------- Modules ----------------
            Item {
                width: parent.width
                height: 14

                Text {
                    text: "MODULES  ·  LEFT TO RIGHT"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }

                Text {
                    anchors.right: parent.right
                    visible: page.island
                    text: "RESET ORDER"
                    color: resetMouse.containsMouse ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2

                    MouseArea {
                        id: resetMouse

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.resetOrder()
                    }
                }

                Text {
                    anchors.right: parent.right
                    visible: !page.island
                    text: "ISLAND ONLY"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            // Rows in island order (left to right). Arrows move a module.
            ListView {
                id: orderList

                width: parent.width
                height: count * 32
                interactive: false
                model: orderModel

                move: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.animMed; easing.type: Easing.OutCubic }
                }

                moveDisplaced: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.animMed; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: moduleRow

                    required property string key
                    required property int index
                    readonly property var info: page.infoFor(key)

                    width: orderList.width
                    height: 32

                    Row {
                        id: arrows

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        opacity: page.island ? 1 : 0.35

                        Repeater {
                            model: [
                                { glyph: 0xF0143, step: -1 },
                                { glyph: 0xF0140, step: 1 }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property int target: moduleRow.index + modelData.step
                                readonly property bool usable: page.island
                                    && target >= 0 && target < orderList.count

                                width: 20
                                height: 20
                                radius: Theme.radius
                                color: arrowMouse.containsMouse && usable
                                    ? Theme.alpha(Theme.accent, 0.14)
                                    : "transparent"
                                border.width: 1
                                border.color: arrowMouse.containsMouse && usable ? Theme.accent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(modelData.glyph)
                                    color: parent.usable ? Theme.textDim : Theme.textFaint
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: arrowMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: parent.usable
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.moveModule(moduleRow.index, parent.target)
                                }
                            }
                        }
                    }

                    ToggleRow {
                        anchors.left: arrows.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        icon: moduleRow.info.icon
                        label: moduleRow.info.label
                        checked: page.modules[moduleRow.key] !== false
                        available: page.loaded && page.island
                        onToggled: page.setModule(moduleRow.key, !checked)
                    }
                }
            }

            // Now-playing visualizer mode
            Item {
                width: parent.width
                height: 28
                opacity: page.island ? 1 : 0.35

                Text {
                    id: vizIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF0EA2)
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                }

                Text {
                    anchors.left: vizIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Music visualizer"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "hover", name: "ON HOVER" },
                            { key: "always", name: "ALWAYS" },
                            { key: "off", name: "OFF" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: page.visualizer === modelData.key

                            width: segText.implicitWidth + 18
                            height: 20
                            radius: Theme.radius
                            color: selected ? Theme.alpha(Theme.accent, 0.16) : "transparent"
                            border.width: 1
                            border.color: selected
                                ? Theme.accent
                                : (segMouse.containsMouse ? Theme.borderAccent : Theme.border)

                            Text {
                                id: segText

                                anchors.centerIn: parent
                                text: parent.modelData.name
                                color: parent.selected ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: segMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: page.island && page.loaded
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    page.visualizer = parent.modelData.key
                                    page.send("visualizer", parent.modelData.key)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---------------- Clock ----------------
            Text {
                text: "CLOCK"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                spacing: 28

                ToggleRow {
                    width: (body.width - 28) / 2
                    icon: page.glyph(0xF051B)
                    label: "Show seconds"
                    checked: page.seconds
                    available: page.loaded

                    onToggled: {
                        page.seconds = !page.seconds
                        page.send("seconds", page.seconds ? "on" : "off")
                    }
                }

                ToggleRow {
                    width: (body.width - 28) / 2
                    icon: page.glyph(0xF00F0)
                    label: "24-hour clock"
                    checked: page.clock24
                    available: page.loaded && page.island

                    onToggled: {
                        page.clock24 = !page.clock24
                        page.send("clock24", page.clock24 ? "on" : "off")
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---------------- Glass ----------------
            Slider {
                width: parent.width
                label: "Top bar opacity  " + Math.round(page.barOpacity * 100) + "%"
                icon: "◐"
                accentColor: Theme.accent
                value: (page.barOpacity - 0.40) / 0.60

                onMoved: function(v) {
                    page.barOpacity = 0.40 + v * 0.60
                    opacityDebounce.restart()
                }

                onCommitted: function(v) {
                    page.barOpacity = 0.40 + v * 0.60
                    opacityDebounce.stop()
                    page.send("opacity", page.barOpacity.toFixed(3))
                }
            }

            Text {
                width: parent.width
                text: page.status !== ""
                    ? page.status
                    : "Super + Shift + W hides or shows the bar."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}

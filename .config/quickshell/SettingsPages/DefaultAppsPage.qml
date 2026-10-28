import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Default Apps: pick the terminal, login shell, file manager,
// browser, editor, viewers and mail client from what is installed.
// scripts/yakushi-defaultsctl.py does the scanning and the writing; this page
// runs it once when opened and once per choice.
Item {
    id: page

    property var hostWindow: null

    property var categories: []
    property var shellInfo: ({ current: "", options: [] })
    property string openKey: ""
    property string status: "Scanning installed apps..."
    property bool busy: false

    readonly property string helper: (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-defaultsctl.py"

    readonly property var glyphs: ({
        terminal: 0xF018D, shell: 0xF07B7, files: 0xF024B, browser: 0xF059F, editor: 0xF0219,
        images: 0xF02E9, video: 0xF0381, audio: 0xF075A, pdf: 0xF0226, mail: 0xF01EE
    })

    function glyph(key) {
        return String.fromCodePoint(glyphs[key] || 0xF0219)
    }

    function iconSource(name) {
        name = String(name || "")
        if (name.charAt(0) === "/")
            return "file://" + name
        return Quickshell.iconPath(name, "application-x-executable")
    }

    function two(n) {
        return (n < 10 ? "0" : "") + n
    }

    function rescan() {
        if (scanProc.running)
            return
        status = "Scanning installed apps..."
        scanProc.running = true
    }

    function choose(key, id) {
        if (busy)
            return
        busy = true
        status = "Saving..."
        setProc.command = key === "shell"
            ? ["python3", helper, "shell", id]
            : ["python3", helper, "set", key, id]
        setProc.running = true
    }

    Process {
        id: scanProc

        command: ["python3", page.helper, "scan"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (!d.ok)
                        throw 0
                    page.categories = d.categories
                    page.shellInfo = d.shell
                    var n = 0
                    for (var i = 0; i < d.categories.length; i++)
                        n += d.categories[i].options.length
                    page.status = "Found " + n + " apps. Pick a category to change it."
                } catch (e) {
                    page.status = "Could not scan the installed apps."
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                page.busy = false
                try {
                    var d = JSON.parse(text)
                    page.status = d.message || ""
                    if (!d.ok)
                        return
                    if (d.shell) {
                        page.shellInfo = { current: d.shell, options: page.shellInfo.options }
                        return
                    }
                    var list = page.categories.slice()
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].key === d.key) {
                            var c = Object.assign({}, list[i])
                            c.current = d.current
                            c.currentName = d.currentName
                            list[i] = c
                        }
                    }
                    page.categories = list
                } catch (e) {
                    page.status = "Could not save."
                }
            }
        }
    }

    // ---------------- Header ----------------
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
            title: "DEFAULT APPS"
        }

        Row {
            id: titleActions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            HeaderButton {
                label: "RESCAN"
                icon: String.fromCodePoint(0xF0450)
                onActivated: page.rescan()
            }
        }
    }

    Text {
        id: statusText

        anchors.top: headerRow.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        text: page.status
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    ScrollHint {
        flick: flick
    }

    Flickable {
        id: flick

        anchors.top: statusText.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: body.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: flick.width
            spacing: Theme.rounded ? 8 : -1

            // Terminal first, then the login shell, then the rest.
            Repeater {
                model: {
                    var list = []
                    for (var i = 0; i < page.categories.length; i++) {
                        list.push(page.categories[i])
                        if (page.categories[i].key === "terminal")
                            list.push({
                                key: "shell",
                                label: "Shell",
                                current: page.shellInfo.current,
                                currentName: page.shellInfo.current.split("/").pop(),
                                options: page.shellInfo.options.map(function(p) {
                                    return { id: p, name: p.split("/").pop(), icon: "", path: p }
                                })
                            })
                    }
                    return list
                }

                delegate: Rectangle {
                    id: block

                    required property var modelData
                    required property int index
                    readonly property bool open: page.openKey === modelData.key
                    readonly property bool isShell: modelData.key === "shell"

                    width: body.width
                    height: head.height + (open ? chips.height + 14 : 0)
                    radius: Theme.rounded ? 12 : 0
                    color: open ? Theme.tint(Theme.accent, 0.05) : Theme.card
                    border.width: 1
                    border.color: open ? Theme.tint(Theme.accent, 0.55) : Theme.tint(Theme.ink, Theme.rounded ? 0.06 : 0.12)
                    clip: true
                    z: open ? 1 : 0

                    Behavior on height {
                        NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                    }

                    // ---- row: index, glyph, label ......... current app, chevron
                    Item {
                        id: head

                        width: parent.width
                        height: 54

                        Text {
                            id: idx

                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !Theme.rounded
                            text: page.two(block.index + 1)
                            color: block.open ? Theme.accent : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            id: catGlyph

                            anchors.left: Theme.rounded ? parent.left : idx.right
                            anchors.leftMargin: Theme.rounded ? 18 : 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            text: page.glyph(block.modelData.key)
                            color: Theme.accent
                            font.family: Theme.glyphs
                            font.pixelSize: 16
                        }

                        Text {
                            anchors.left: catGlyph.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.rounded ? block.modelData.label : block.modelData.label.toUpperCase()
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 12
                            font.bold: !Theme.rounded
                            font.letterSpacing: Theme.rounded ? 0.5 : 2
                        }

                        Text {
                            id: chevron

                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(block.open ? 0xF0143 : 0xF0140)
                            color: Theme.inkSoft
                            font.family: Theme.glyphs
                            font.pixelSize: 16
                        }

                        Row {
                            anchors.right: chevron.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9

                            Image {
                                visible: !block.isShell && block.modelData.current !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                sourceSize.width: 40
                                sourceSize.height: 40
                                asynchronous: true
                                source: {
                                    var opts = block.modelData.options
                                    for (var i = 0; i < opts.length; i++)
                                        if (opts[i].id === block.modelData.current)
                                            return page.iconSource(opts[i].icon)
                                    return ""
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: block.modelData.currentName !== ""
                                    ? block.modelData.currentName
                                    : (block.modelData.options.length > 0 ? "Not set" : "None installed")
                                color: block.modelData.currentName !== "" ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: block.modelData.options.length > 0
                            onClicked: page.openKey = block.open ? "" : block.modelData.key
                        }
                    }

                    // ---- choices
                    Flow {
                        id: chips

                        anchors.top: head.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8
                        opacity: block.open ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.tFast }
                        }

                        Repeater {
                            model: block.open ? block.modelData.options : []

                            delegate: Rectangle {
                                id: chip

                                required property var modelData
                                readonly property bool selected: modelData.id === block.modelData.current
                                    || (block.isShell && modelData.name === block.modelData.currentName)

                                width: chipRow.implicitWidth + 24
                                height: 36
                                radius: Theme.corner
                                color: selected
                                    ? Theme.tint(Theme.accent, 0.16)
                                    : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : Theme.tint(Theme.ink, 0.02)
                                border.width: 1
                                border.color: selected
                                    ? Theme.accent
                                    : chipMouse.containsMouse ? Theme.lineHot : Theme.line
                                opacity: page.busy && !selected ? 0.5 : 1

                                Row {
                                    id: chipRow

                                    anchors.centerIn: parent
                                    spacing: 8

                                    Image {
                                        visible: !block.isShell
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                        asynchronous: true
                                        source: block.isShell ? "" : page.iconSource(chip.modelData.icon)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.name
                                        color: chip.selected ? Theme.accent : Theme.ink
                                        font.family: Theme.mono
                                        font.pixelSize: 12
                                        font.bold: chip.selected
                                    }

                                    Text {
                                        visible: block.isShell
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.path || ""
                                        color: Theme.inkSoft
                                        font.family: Theme.mono
                                        font.pixelSize: 10
                                    }
                                }

                                MouseArea {
                                    id: chipMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !page.busy && !chip.selected
                                    onClicked: page.choose(block.modelData.key, chip.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                width: 1
                height: 10
            }

            Text {
                width: body.width
                text: "Files and links open with your choice (mimeapps.list). Terminal, file manager and browser are also what SUPER + Q / E / B open. Changing the shell asks for your password; it applies after you log out and back in."
                wrapMode: Text.WordWrap
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }
}

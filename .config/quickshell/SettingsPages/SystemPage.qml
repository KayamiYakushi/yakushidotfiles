import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"

// Settings -> System: your picture, the machine and live load.
// Facts come from scripts/yakushi-sysinfo.py and yakushi-gpuinfo.py (once,
// when the page opens); load, memory and uptime are read from /proc and
// sysfs every 2 seconds, only while this page is open.
Item {
    id: page

    property var hostWindow: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scripts: home + "/.config/quickshell/scripts/"

    // ---- facts
    property var facts: ({ host: "...", os: "...", kernel: "...", user: "...", cpu: "...", storage: "..." })
    property real diskUse: -1
    property string gpuName: "..."
    property string uptime: "..."
    property string memory: "..."
    property real memUse: -1
    property real cpuUse: -1
    property real gpuUse: -1
    property string vram: ""

    // ---- picture (assets/system-profile, chosen with the in-card picker)
    property int pictureRev: 0
    readonly property url picture: "file://" + home + "/.config/quickshell/assets/system-profile"
        + (pictureRev > 0 ? "?v=" + pictureRev : "")

    function pickPicture() {
        if (!hostWindow)
            return
        hostWindow.openImagePicker(home, home + "/Pictures", function(path) {
            savePicture.command = ["python3", page.scripts + "yakushi-profile-image.py", path]
            savePicture.running = true
        })
    }

    Process {
        id: savePicture
        onExited: function(code) { if (code === 0) page.pictureRev += 1 }
    }

    // ---- one-off facts
    Process {
        command: ["python3", page.scripts + "yakushi-sysinfo.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.facts = JSON.parse(text)
                    page.diskUse = page.facts.storageFraction
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: diskCheck
        command: ["python3", page.scripts + "yakushi-sysinfo.py", "disk"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    page.facts = Object.assign({}, page.facts, d)
                    page.diskUse = d.storageFraction
                } catch (e) {
                }
            }
        }
    }

    // GPU: exact model and where its load / VRAM can be read
    property string gpuBusyFile: ""
    property string vramUsedFile: ""
    property string vramTotalFile: ""
    property bool nvidia: false

    Process {
        command: ["python3", page.scripts + "yakushi-gpuinfo.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var g = JSON.parse(text)
                    page.gpuName = g.name || "Unknown GPU"
                    page.gpuBusyFile = g.busy || ""
                    page.vramUsedFile = g.vramUsed || ""
                    page.vramTotalFile = g.vramTotal || ""
                    page.nvidia = g.nvidia === true
                    page.tick()
                } catch (e) {
                    page.gpuName = "Unknown GPU"
                }
            }
        }
    }

    // ---- live numbers
    function gb(bytes) {
        return (bytes / 1073741824).toFixed(1)
    }

    property var lastCpu: null

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            var f = (text().split("\n")[0] || "").trim().split(/\s+/).slice(1, 9).map(Number)
            if (f.length < 5)
                return
            var idle = f[3] + f[4]
            var all = f.reduce(function(a, b) { return a + b }, 0)
            if (page.lastCpu && all > page.lastCpu.all)
                page.cpuUse = Math.min(1, Math.max(0, 1 - (idle - page.lastCpu.idle) / (all - page.lastCpu.all)))
            page.lastCpu = { idle: idle, all: all }
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            var kb = {}
            text().split("\n").forEach(function(l) {
                var m = /^(\w+):\s+(\d+)/.exec(l)
                if (m)
                    kb[m[1]] = Number(m[2])
            })
            if (!kb.MemTotal)
                return
            var used = kb.MemTotal - (kb.MemAvailable || 0)
            page.memory = page.gb(used * 1024) + " / " + page.gb(kb.MemTotal * 1024) + " GB"
            page.memUse = used / kb.MemTotal
        }
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: {
            var s = Math.floor(parseFloat(text()))
            if (isNaN(s))
                return
            var d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60
            page.uptime = (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
        }
    }

    FileView {
        id: gpuBusy
        path: page.gpuBusyFile
        printErrors: false
        onLoaded: {
            var v = parseInt(text())
            if (!isNaN(v))
                page.gpuUse = Math.min(1, Math.max(0, v / 100))
        }
    }

    property real vramTotal: 0

    FileView {
        path: page.vramTotalFile
        printErrors: false
        onLoaded: page.vramTotal = Number(text().trim()) || 0
    }

    FileView {
        id: vramUsed
        path: page.vramUsedFile
        printErrors: false
        onLoaded: {
            var used = Number(text().trim())
            if (page.vramTotal > 0 && !isNaN(used))
                page.vram = "VRAM  " + page.gb(used) + " / " + page.gb(page.vramTotal) + " GB"
        }
    }

    Process {
        id: smi
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = text.split("\n")[0].split(",").map(function(x) { return Number(x) })
                if (v.length === 3 && !isNaN(v[0])) {
                    page.gpuUse = Math.min(1, v[0] / 100)
                    page.vram = "VRAM  " + (v[1] / 1024).toFixed(1) + " / " + (v[2] / 1024).toFixed(1) + " GB"
                }
            }
        }
    }

    function tick() {
        stat.reload()
        meminfo.reload()
        uptimeFile.reload()
        if (gpuBusyFile !== "")
            gpuBusy.reload()
        if (vramUsedFile !== "")
            vramUsed.reload()
        if (nvidia && !smi.running)
            smi.running = true
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: page.tick()
    }

    Timer {
        // the disk changes slowly
        interval: 60000
        running: true
        repeat: true
        onTriggered: diskCheck.running = true
    }

    function percent(f) {
        return f >= 0 ? Math.round(f * 100) + "%" : ""
    }

    readonly property color onAccent: 0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b > 0.55
        ? "#0a0a0a" : "#f5f5f5"

    // the four hardware entries, shared by both styles
    readonly property var hardware: [
        { tag: "01", name: "CPU", glyph: 0xF0EE0, value: facts.cpu, extra: "", load: cpuUse },
        { tag: "02", name: "GPU", glyph: 0xF08AE, value: gpuName, extra: vram, load: gpuUse },
        { tag: "03", name: "MEMORY", glyph: 0xF035B, value: memory, extra: "", load: memUse },
        { tag: "04", name: "STORAGE", glyph: 0xF02CA, value: facts.storage, extra: "", load: diskUse }
    ]

    // ==================================================================
    // Sharp style: picture + host, a ruled facts strip, a 2 x 2 table
    // ==================================================================
    Column {
        visible: !Theme.rounded
        anchors.fill: parent
        spacing: 18

        PageTitle {
            width: parent.width
            title: "SYSTEM"
        }

        Item {
            width: parent.width
            height: 148

            Rectangle {
                id: frame

                width: 148
                height: 148
                color: Theme.tint(Theme.ink, 0.03)
                border.width: 1
                border.color: frameMouse.containsMouse ? Theme.accent : Theme.tint(Theme.ink, 0.18)
                clip: true

                Image {
                    id: shot

                    anchors.fill: parent
                    anchors.margins: 5
                    source: page.picture
                    sourceSize.width: 280
                    sourceSize.height: 280
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Text {
                    id: plus

                    visible: shot.status !== Image.Ready
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 46
                    text: "+"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 26
                }

                Text {
                    visible: plus.visible
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: plus.bottom
                    anchors.topMargin: 6
                    text: "ADD IMAGE"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 3
                }

                Rectangle {
                    visible: shot.status === Image.Ready && frameMouse.containsMouse
                    x: 5
                    y: parent.height - height - 5
                    width: parent.width - 10
                    height: 24
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "CHANGE ──"
                        color: page.onAccent
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 3
                    }
                }

                MouseArea {
                    id: frameMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.pickPicture()
                }
            }

            // corner ticks on the picture
            Rectangle { x: -3; y: -3; width: 10; height: 2; color: Theme.accent }
            Rectangle { x: -3; y: -3; width: 2; height: 10; color: Theme.accent }
            Rectangle { x: frame.width - 7; y: frame.height + 1; width: 10; height: 2; color: Theme.accent }
            Rectangle { x: frame.width + 1; y: frame.height - 7; width: 2; height: 10; color: Theme.accent }

            Item {
                anchors.left: frame.right
                anchors.leftMargin: 22
                anchors.right: parent.right
                height: parent.height

                Text {
                    id: tag

                    y: 2
                    text: "// HOST"
                    color: Theme.accent
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 3
                }

                Text {
                    id: hostName

                    anchors.top: tag.bottom
                    anchors.topMargin: 4
                    width: parent.width
                    text: String(page.facts.host).toUpperCase()
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 34
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    anchors.top: hostName.bottom
                    anchors.topMargin: 2
                    width: parent.width
                    text: page.facts.os
                    elide: Text.ElideRight
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                // uptime | kernel | user
                Rectangle {
                    id: factStrip

                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 50
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.tint(Theme.ink, 0.12)

                    Repeater {
                        model: [
                            { k: "UPTIME", v: page.uptime, from: 0.0, to: 0.32 },
                            { k: "KERNEL", v: page.facts.kernel, from: 0.32, to: 0.74 },
                            { k: "USER", v: page.facts.user, from: 0.74, to: 1.0 }
                        ]

                        delegate: Item {
                            required property var modelData
                            required property int index

                            x: factStrip.width * modelData.from
                            width: factStrip.width * (modelData.to - modelData.from)
                            height: factStrip.height

                            Rectangle {
                                visible: parent.index > 0
                                width: 1
                                height: parent.height
                                color: Theme.tint(Theme.ink, 0.12)
                            }

                            Text {
                                id: key

                                x: 14
                                y: 9
                                text: parent.modelData.k
                                color: Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 2
                            }

                            Text {
                                x: 14
                                anchors.top: key.bottom
                                anchors.topMargin: 5
                                width: parent.width - 24
                                text: parent.modelData.v
                                elide: Text.ElideRight
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }

        // HARDWARE ─────────────── ハードウェア
        Item {
            width: parent.width
            height: 14

            Text {
                id: hwLabel

                anchors.verticalCenter: parent.verticalCenter
                text: "HARDWARE"
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 3
            }

            Text {
                id: hwJp

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "ハードウェア"
                color: Theme.inkSoft
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 11
            }

            Rectangle {
                anchors.left: hwLabel.right
                anchors.leftMargin: 12
                anchors.right: hwJp.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.tint(Theme.ink, 0.08)
            }
        }

        Grid {
            id: table

            width: parent.width
            columns: 2
            // neighbouring cells share their 1 px rule
            columnSpacing: -1
            rowSpacing: -1

            Repeater {
                model: page.hardware

                delegate: Rectangle {
                    id: cell

                    required property var modelData
                    readonly property real load: modelData.load
                    readonly property bool hot: load > 0.9

                    width: (table.width + 1) / 2
                    height: 122
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.tint(Theme.ink, 0.12)

                    Text {
                        id: cellTag

                        x: 16
                        y: 14
                        text: cell.modelData.tag
                        color: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Text {
                        anchors.left: cellTag.right
                        anchors.leftMargin: 10
                        anchors.baseline: cellTag.baseline
                        text: cell.modelData.name
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        y: 8
                        visible: cell.load >= 0
                        text: page.percent(cell.load)
                        color: cell.hot ? Theme.alert : Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 22
                        font.bold: true
                    }

                    Text {
                        id: cellValue

                        x: 16
                        anchors.top: cellTag.bottom
                        anchors.topMargin: 12
                        width: parent.width - 32
                        text: cell.modelData.value
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }

                    Text {
                        x: 16
                        anchors.top: cellValue.bottom
                        anchors.topMargin: 4
                        visible: cell.modelData.extra !== ""
                        text: cell.modelData.extra
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }

                    // load as 24 blocks
                    Row {
                        id: blocks

                        readonly property int count: 24
                        readonly property int lit: Math.round(Math.min(1, Math.max(0, cell.load)) * count)

                        visible: cell.load >= 0
                        x: 16
                        y: parent.height - 22
                        width: parent.width - 32
                        spacing: 2

                        Repeater {
                            model: blocks.count

                            Rectangle {
                                required property int index

                                width: (blocks.width - blocks.spacing * (blocks.count - 1)) / blocks.count
                                height: 8
                                color: index < blocks.lit
                                    ? (cell.hot ? Theme.alert : Theme.accent)
                                    : Theme.tint(Theme.ink, 0.07)
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================================================================
    // Rounded style: a soft hero card and four small cards
    // ==================================================================
    Column {
        visible: Theme.rounded
        anchors.fill: parent
        spacing: 18

        PageTitle {
            width: parent.width
            title: "SYSTEM"
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
        }

        Rectangle {
            width: parent.width
            height: 148
            radius: 14
            color: Theme.card
            border.width: 1
            border.color: Theme.line

            ClippingRectangle {
                id: avatar

                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 120
                height: 120
                radius: 14
                color: Theme.tint(Theme.ink, 0.04)
                border.width: avatarMouse.containsMouse ? 1 : 0
                border.color: Theme.accent

                Image {
                    id: avatarImage

                    anchors.fill: parent
                    source: page.picture
                    sourceSize.width: 240
                    sourceSize.height: 240
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Column {
                    visible: avatarImage.status !== Image.Ready
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(0xF02E9)
                        color: Theme.inkSoft
                        font.family: Theme.glyphs
                        font.pixelSize: 22
                    }

                    Text {
                        text: "ADD IMAGE"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }

                Rectangle {
                    visible: avatarImage.status === Image.Ready && avatarMouse.containsMouse
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 26
                    color: Theme.tint("#000000", 0.7)

                    Text {
                        anchors.centerIn: parent
                        text: "CHANGE"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }

                MouseArea {
                    id: avatarMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.pickPicture()
                }
            }

            Column {
                anchors.left: avatar.right
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    width: parent.width
                    text: page.facts.host
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 22
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: page.facts.os
                    elide: Text.ElideRight
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                Item {
                    width: 1
                    height: 4
                }

                Rectangle {
                    width: upGlyph.implicitWidth + upText.implicitWidth + 24
                    height: 24
                    radius: 12
                    color: Theme.tint(Theme.accent, 0.12)

                    Text {
                        id: upGlyph

                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF051B)
                        color: Theme.accent
                        font.family: Theme.glyphs
                        font.pixelSize: 11
                    }

                    Text {
                        id: upText

                        anchors.left: upGlyph.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "up " + page.uptime
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }
                }
            }
        }

        Grid {
            id: cards

            width: parent.width
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            Repeater {
                model: page.hardware

                delegate: Rectangle {
                    id: card

                    required property var modelData

                    width: (cards.width - cards.columnSpacing) / 2
                    height: 104
                    radius: 12
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.line

                    Rectangle {
                        id: chip

                        x: 14
                        y: 14
                        width: 30
                        height: 30
                        radius: 9
                        color: Theme.tint(Theme.accent, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(card.modelData.glyph)
                            color: Theme.accent
                            font.family: Theme.glyphs
                            font.pixelSize: 15
                        }
                    }

                    Text {
                        anchors.left: chip.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: chip.verticalCenter
                        text: card.modelData.name
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    Text {
                        x: 14
                        anchors.top: chip.bottom
                        anchors.topMargin: 10
                        width: parent.width - 28
                        text: card.modelData.value
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 12
                    }

                    Rectangle {
                        visible: card.modelData.load >= 0
                        x: 14
                        y: parent.height - 18
                        width: parent.width - 28
                        height: 4
                        radius: 2
                        color: Theme.tint(Theme.ink, 0.08)

                        Rectangle {
                            width: parent.width * Math.min(1, Math.max(0, card.modelData.load))
                            height: parent.height
                            radius: 2
                            color: card.modelData.load > 0.9 ? Theme.alert : Theme.accent

                            Behavior on width {
                                NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}

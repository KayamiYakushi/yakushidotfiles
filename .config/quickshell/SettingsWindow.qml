import Quickshell
import Quickshell.Wayland
import QtQuick
import "SettingsPages"

// The Settings panel (SUPER + I): a card in the middle of the screen with
// the page list on the left and the chosen page on the right: a header strip
// and a numbered page list. The card leans toward the pointer
// (TiltCard). Clicking outside the card or Esc closes it.
PanelWindow {
    id: settings

    signal dismissed()

    property bool showing: false
    property int page: 0

    // An outside dialog (the SDDM file chooser) needs the screen for a
    // moment: Settings steps back while any is open.
    property int dialogs: 0
    readonly property bool stepAside: dialogs > 0

    function beginExternalDialog() { dialogs += 1 }
    function endExternalDialog() { dialogs = Math.max(0, dialogs - 1) }

    // show(), or show("Tasks") to open on that page
    function show(start) {
        page = Math.max(0, pageIndex(start || ""))
        // always opens at its default size, in the middle
        Theme.settingsWidth = 0
        Theme.settingsHeight = 0
        card.offsetX = 0
        card.offsetY = 0
        showing = true
    }

    function pageIndex(name) {
        var n = String(name).toLowerCase()
        for (var i = 0; i < pages.length; i++)
            if (pages[i].name.toLowerCase() === n || pages[i].file.toLowerCase() === n + "page")
                return i
        return -1
    }

    function hide() {
        if (!showing)
            return
        picker.opened = false
        saved.flush()
        showing = false
        dismissed()
    }

    function toggle() {
        if (showing)
            hide()
        else
            show()
    }

    // In-card image chooser shared by System and Login Screen.
    // `done(path)` runs with the chosen file.
    function openImagePicker(homeDir, startDir, done) {
        picker.whenChosen = done
        picker.homeDir = homeDir
        picker.openAt(startDir)
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // hyprland keybinds.lua looks for this name: while Settings is open,
    // SUPER + mouse goes to Settings instead of moving / resizing windows
    WlrLayershell.namespace: "yakushi-settings"
    WlrLayershell.layer: stepAside ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: showing && !stepAside ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Takes no input at all while closed.
    mask: Region {
        item: settings.showing && !settings.stepAside ? outside : null
    }

    ThemeState {
        id: saved
    }

    readonly property var pages: [
        { name: "System",       jp: "システム",       file: "SystemPage",      glyph: "󰒓" },
        { name: "Tasks",        jp: "タスク",         file: "TasksPage",       glyph: String.fromCodePoint(0xF04C5) },
        { name: "Appearance",   jp: "外観",           file: "AppearancePage",  glyph: "󰏘" },
        { name: "Top Bar",      jp: "トップバー",     file: "TopBarPage",      glyph: String.fromCodePoint(0xF1513) },
        { name: "Login Screen", jp: "ログイン画面",   file: "LoginScreenPage", glyph: "󰌾" },
        { name: "Keybinds",     jp: "キー設定",       file: "KeybindsPage",    glyph: "󰌌" },
        { name: "Default Apps", jp: "既定アプリ",     file: "DefaultAppsPage", glyph: String.fromCodePoint(0xF003B) },
        { name: "Input",        jp: "入力",           file: "InputPage",       glyph: "󰍽" },
        { name: "Sound",        jp: "サウンド",       file: "SoundPage",       glyph: "" },
        { name: "Monitors",     jp: "モニター",       file: "MonitorsPage",    glyph: "" },
        // these two keep their own right margin
        { name: "Network",      jp: "ネットワーク",   file: "NetworkPage",     glyph: "", ownMargin: true },
        { name: "Bluetooth",    jp: "ブルートゥース", file: "BluetoothPage",   glyph: "󰂯", ownMargin: true }
    ]

    function two(n) {
        return n < 10 ? "0" + n : String(n)
    }

    // black or white, whichever reads on the accent
    readonly property color onAccent: 0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b > 0.55
        ? "#0a0a0a" : "#f5f5f5"

    // L-shaped accent mark at a corner of the card
    component CornerMark: Item {
        property bool atRight: false
        property bool atBottom: false

        width: 18
        height: 18

        Rectangle {
            y: parent.atBottom ? parent.height - 2 : 0
            width: parent.width
            height: 2
            color: Theme.accent
        }

        Rectangle {
            x: parent.atRight ? parent.width - 2 : 0
            width: 2
            height: parent.height
            color: Theme.accent
        }
    }

    // ------------------------------------------------------------------
    // Outside the card: click to close, Esc anywhere
    // ------------------------------------------------------------------
    Item {
        id: outside

        anchors.fill: parent
        focus: settings.showing

        Keys.onEscapePressed: picker.opened ? picker.dismiss() : settings.hide()

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // SUPER + click (a slip while moving the card) does not close it
            onClicked: mouse => {
                if (!(mouse.modifiers & Qt.MetaModifier))
                    settings.hide()
            }
        }
    }

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    TiltCard {
        id: card

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: offsetX
        anchors.verticalCenterOffset: offsetY

        // Move: drag the header strip, or SUPER + left drag anywhere on it.
        // Resize: drag an edge or a corner, or SUPER + right drag (the side
        // you grab follows the pointer, the opposite one stays). Double-click
        // an edge for the default size. Nothing is saved: it always opens at
        // the default size, in the middle.
        property real offsetX: 0
        property real offsetY: 0
        readonly property int minW: Math.min(860, settings.width - 40)
        readonly property int minH: Math.min(560, settings.height - 40)
        width: Math.max(minW, Math.min(Theme.settingsWidth > 0 ? Theme.settingsWidth : 1020, settings.width - 40))
        height: Math.max(minH, Math.min(Theme.settingsHeight > 0 ? Theme.settingsHeight : 660, settings.height - 40))
        still: resizer.active || resizer.hovering > 0
        shown: settings.showing

        // clicks on the card stay on the card
        MouseArea {
            anchors.fill: parent
        }

        // ---- moving and resizing
        Item {
            id: resizer

            property bool active: false
            property int hovering: 0             // handles under the pointer: the card stops leaning
            property string mode: ""             // move | resize
            property int sx: 0                   // which sides follow the pointer (-1 / 0 / 1)
            property int sy: 0
            property real startW: 0
            property real startH: 0
            property real startX: 0
            property real startY: 0
            property point startAt: Qt.point(0, 0)

            anchors.fill: parent
            z: 20

            function begin(area, mouse, how, sideX, sideY) {
                startAt = area.mapToItem(null, mouse.x, mouse.y)
                startW = card.width
                startH = card.height
                startX = card.offsetX
                startY = card.offsetY
                mode = how
                sx = sideX
                sy = sideY
                active = true
            }

            // keep the card (mostly) on the screen
            function clampOffsets() {
                var maxX = Math.max(0, (settings.width - card.width) / 2 + card.width / 2 - 80)
                var maxY = Math.max(0, (settings.height - card.height) / 2 + card.height / 2 - 60)
                card.offsetX = Math.max(-maxX, Math.min(maxX, card.offsetX))
                card.offsetY = Math.max(-maxY, Math.min(maxY, card.offsetY))
            }

            function drag(area, mouse) {
                if (!active)
                    return
                var p = area.mapToItem(null, mouse.x, mouse.y)
                var dx = p.x - startAt.x
                var dy = p.y - startAt.y
                if (mode === "move") {
                    card.offsetX = startX + dx
                    card.offsetY = startY + dy
                } else {
                    if (sx !== 0) {
                        var w = Math.round(Math.max(card.minW, Math.min(settings.width - 40, startW + sx * dx)))
                        Theme.settingsWidth = w
                        card.offsetX = startX + sx * (w - startW) / 2
                    }
                    if (sy !== 0) {
                        var h = Math.round(Math.max(card.minH, Math.min(settings.height - 40, startH + sy * dy)))
                        Theme.settingsHeight = h
                        card.offsetY = startY + sy * (h - startH) / 2
                    }
                }
                clampOffsets()
            }

            function finish() {
                active = false
                mode = ""
            }

            function reset() {
                Theme.settingsWidth = 0
                Theme.settingsHeight = 0
            }

            // SUPER + left drag moves, SUPER + right drag resizes; anything
            // else goes through to the page underneath
            MouseArea {
                id: gesture

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                // no cursorShape here: it would hide the hand cursor of every button
                onPressed: mouse => {
                    if (!(mouse.modifiers & Qt.MetaModifier)) {
                        mouse.accepted = false
                        return
                    }
                    if (mouse.button === Qt.RightButton)
                        resizer.begin(gesture, mouse, "resize",
                                      mouse.x < width / 2 ? -1 : 1, mouse.y < height / 2 ? -1 : 1)
                    else
                        resizer.begin(gesture, mouse, "move", 0, 0)
                }
                onPositionChanged: mouse => resizer.drag(gesture, mouse)
                onReleased: resizer.finish()
                onCanceled: resizer.finish()
            }

            // the header strip moves the card with a plain left drag
            MouseArea {
                id: handle

                width: parent.width
                height: 46
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                onPressed: mouse => resizer.begin(handle, mouse, "move", 0, 0)
                onPositionChanged: mouse => resizer.drag(handle, mouse)
                onReleased: resizer.finish()
                onCanceled: resizer.finish()
                onDoubleClicked: {
                    card.offsetX = 0
                    card.offsetY = 0
                }
            }

            // edges and corners, a few pixels wide
            Repeater {
                // [x side, y side]: -1 left/top, 1 right/bottom, 0 none
                model: [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]

                delegate: MouseArea {
                    id: grab

                    required property var modelData
                    readonly property int gx: modelData[0]
                    readonly property int gy: modelData[1]
                    readonly property int grip: 8

                    x: gx < 0 ? -grip / 2 : gx > 0 ? resizer.width - grip / 2 : grip
                    y: gy < 0 ? -grip / 2 : gy > 0 ? resizer.height - grip / 2 : grip
                    width: gx !== 0 ? grip : resizer.width - 2 * grip
                    height: gy !== 0 ? grip : resizer.height - 2 * grip
                    z: gx !== 0 && gy !== 0 ? 2 : 1
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: gx !== 0 && gy !== 0 ? (gx === gy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                        : gx !== 0 ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    onPressed: mouse => resizer.begin(grab, mouse, "resize", grab.gx, grab.gy)
                    onPositionChanged: mouse => resizer.drag(grab, mouse)
                    onReleased: resizer.finish()
                    onCanceled: resizer.finish()
                    onDoubleClicked: resizer.reset()
                    onContainsMouseChanged: resizer.hovering = Math.max(0, resizer.hovering + (containsMouse ? 1 : -1))
                }
            }
        }

        // petals drift over the card with the Sakura accent only
        SakuraPetals {
            anchors.fill: parent
            z: 10
            active: Qt.colorEqual(Theme.accent, "#ff7a9d")
            tint: Theme.accent
        }

        Rectangle {
            id: frame

            anchors.fill: parent
            color: Theme.backdrop
            border.width: 1
            border.color: Theme.tint(Theme.ink, 0.12)

            CornerMark { x: -4; y: -4 }
            CornerMark { x: frame.width - width + 4; y: -4; atRight: true }
            CornerMark { x: -4; y: frame.height - height + 4; atBottom: true }
            CornerMark { x: frame.width - width + 4; y: frame.height - height + 4; atRight: true; atBottom: true }

            // ============ header strip ============
            Item {
                id: strip

                width: parent.width
                height: 46

                Row {
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "薬"
                        color: Theme.alert
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SETTINGS"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 6
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "設定"
                        color: Theme.inkSoft
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 13
                        font.letterSpacing: 3
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.pages[settings.page].jp
                        color: Theme.inkSoft
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 14
                        color: Theme.tint(Theme.ink, 0.18)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.two(settings.page + 1) + " / " + settings.two(settings.pages.length)
                        color: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 2
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.tint(Theme.ink, 0.12)
                }
            }

            // ============ numbered page list ============
            Item {
                id: list

                y: strip.height
                width: 256
                height: parent.height - strip.height

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.tint(Theme.ink, 0.12)
                }

                Column {
                    y: 14
                    width: parent.width - 1

                    Repeater {
                        model: settings.pages

                        delegate: Rectangle {
                            id: line

                            required property var modelData
                            required property int index
                            readonly property bool here: settings.page === index
                            readonly property color ink: here ? settings.onAccent : Theme.ink

                            width: parent.width
                            height: 36
                            color: here ? Theme.accent : lineMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: Theme.tFast }
                            }

                            // hover tick on the left edge
                            Rectangle {
                                visible: lineMouse.containsMouse && !line.here
                                width: 3
                                height: parent.height
                                color: Theme.accent
                            }

                            Text {
                                id: number

                                x: 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: settings.two(line.index + 1)
                                color: line.here ? line.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.bold: line.here
                            }

                            Text {
                                anchors.left: number.right
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.modelData.name.toUpperCase()
                                color: line.here || lineMouse.containsMouse ? line.ink : Theme.tint(Theme.ink, 0.78)
                                font.family: Theme.mono
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.5
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.modelData.jp
                                color: line.here ? Theme.tint(line.ink, 0.8) : Theme.inkSoft
                                font.family: "Noto Sans CJK JP"
                                font.pixelSize: 11
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: lineMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settings.page = line.index
                            }
                        }
                    }
                }

                // 薬師 (Yakushi), large and faint
                Text {
                    x: 18
                    anchors.bottom: listFoot.top
                    anchors.bottomMargin: 10
                    text: "薬\n師"
                    lineHeight: 0.92
                    color: Theme.tint(Theme.ink, 0.09)
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 58
                    font.bold: true
                }

                Item {
                    id: listFoot

                    anchors.bottom: parent.bottom
                    width: parent.width - 1
                    height: 40

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.tint(Theme.ink, 0.12)
                    }

                    Text {
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ESC ── CLOSE"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }
            }

            // ============ the page ============
            Item {
                x: list.width + 28
                y: strip.height + 20
                width: parent.width - x
                height: parent.height - y - 16
                clip: true

                Loader {
                    id: view

                    anchors.fill: parent
                    anchors.rightMargin: settings.pages[settings.page].ownMargin ? 0 : 28
                    source: "SettingsPages/" + settings.pages[settings.page].file + ".qml"
                    onLoaded: item.hostWindow = settings

                    // each page fades in
                    onSourceChanged: {
                        opacity = 0
                        fade.restart()
                    }

                    NumberAnimation {
                        id: fade

                        target: view
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.tMid
                    }

                    Component.onCompleted: fade.restart()
                }
            }

            // ============ image chooser, over the whole card ============
            ImagePicker {
                id: picker

                property var whenChosen: null

                anchors.fill: parent
                z: 100

                onAccepted: function(path) {
                    if (whenChosen)
                        whenChosen(path)
                    whenChosen = null
                }

                onClosed: outside.forceActiveFocus()
            }
        }
    }
}

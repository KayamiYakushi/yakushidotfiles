import Quickshell
import Quickshell.Wayland
import QtQuick
import "SettingsPages"

// The Settings panel (SUPER + I): a card in the middle of the screen with
// the page list on the left and the chosen page on the right. Two looks,
// picked in Appearance -> Style: sharp (header strip, numbered list) and
// rounded (floating side menu). The card leans toward the pointer
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

    function show() {
        page = 0
        showing = true
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

    // L-shaped accent mark at a corner of the sharp card
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
            onClicked: settings.hide()
        }
    }

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    TiltCard {
        id: card

        anchors.centerIn: parent
        width: Math.min(1020, settings.width - 80)
        height: Math.min(660, settings.height - 80)
        shown: settings.showing

        // clicks on the card stay on the card
        MouseArea {
            anchors.fill: parent
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
            radius: Theme.rounded ? 18 : 0
            border.width: 1
            border.color: Theme.rounded ? Theme.tint(Theme.accent, 0.35) : Theme.tint(Theme.ink, 0.12)

            CornerMark { visible: !Theme.rounded; x: -4; y: -4 }
            CornerMark { visible: !Theme.rounded; x: frame.width - width + 4; y: -4; atRight: true }
            CornerMark { visible: !Theme.rounded; x: -4; y: frame.height - height + 4; atBottom: true }
            CornerMark { visible: !Theme.rounded; x: frame.width - width + 4; y: frame.height - height + 4; atRight: true; atBottom: true }

            // ============ sharp: header strip ============
            Item {
                id: strip

                visible: !Theme.rounded
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

            // ============ sharp: numbered list ============
            Item {
                id: list

                visible: !Theme.rounded
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

            // ============ rounded: floating side menu ============
            Rectangle {
                id: menu

                visible: Theme.rounded
                x: 16
                y: 16
                width: 252
                height: parent.height - 32
                radius: 14
                color: Theme.tint(Theme.ink, 0.025)
                border.width: 1
                border.color: Theme.tint(Theme.ink, 0.04)

                Row {
                    x: 18
                    y: 18
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "薬"
                        color: Theme.alert
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 28
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SETTINGS"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 4
                    }
                }

                Column {
                    x: 12
                    y: 70
                    width: parent.width - 24
                    spacing: 3

                    Repeater {
                        model: settings.pages

                        delegate: Rectangle {
                            id: pill

                            required property var modelData
                            required property int index
                            readonly property bool here: settings.page === index

                            width: parent.width
                            height: 38
                            radius: 10
                            color: here ? Theme.tint(Theme.accent, 0.14)
                                : pillMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"
                            border.width: here ? 1 : 0
                            border.color: Theme.tint(Theme.accent, 0.45)

                            Behavior on color {
                                ColorAnimation { duration: Theme.tFast }
                            }

                            Text {
                                id: pillGlyph

                                x: 12
                                width: 18
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: pill.modelData.glyph
                                color: pill.here ? Theme.accent : Theme.inkSoft
                                font.family: Theme.glyphs
                                font.pixelSize: 14
                            }

                            Text {
                                anchors.left: pillGlyph.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: pill.modelData.name
                                color: pill.here || pillMouse.containsMouse ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: pill.modelData.jp
                                color: pill.here ? Theme.tint(Theme.accent, 0.85) : Theme.inkMute
                                font.family: "Noto Sans CJK JP"
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: pillMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settings.page = pill.index
                            }
                        }
                    }
                }

                Text {
                    x: 18
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    text: "ESC  ·  close"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            // ============ the page ============
            Item {
                x: Theme.rounded ? menu.x + menu.width + 24 : list.width + 28
                y: Theme.rounded ? 28 : strip.height + 20
                width: parent.width - x - (Theme.rounded ? 16 : 0)
                height: parent.height - y - (Theme.rounded ? 22 : 16)
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

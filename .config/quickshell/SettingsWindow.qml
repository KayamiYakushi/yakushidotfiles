
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import "SettingsPages"

PanelWindow {
    id: root

    signal dismissed()

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: root.externalDialogOpen ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (root.showing && !root.externalDialogOpen) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Only actually grab input/paint when open - mirrors the OSD's mask trick
    // so the window is a no-op on the compositor while closed.
    mask: Region {
        item: (root.showing && !root.externalDialogOpen) ? backdrop : null
    }

    ThemeState {
        id: themeState
    }

    property bool showing: false
    property int externalDialogDepth: 0
    property bool externalDialogOpen: externalDialogDepth > 0

    function beginExternalDialog() {
        externalDialogDepth += 1
    }

    function endExternalDialog() {
        externalDialogDepth = Math.max(0, externalDialogDepth - 1)
    }

    function show() {
        selectedIndex = 0
        showing = true
    }

    function hide() {
        if (!showing)
            return

        imagePicker.opened = false
        themeState.flush()
        showing = false
        dismissed()
    }

    // Opens the in-panel image picker. `callback(path)` runs when an image
    // is chosen. The picker lives inside the Settings card, so it shares the
    // same surface, animation and keyboard focus as everything else here.
    function openImagePicker(homeDir, startDir, callback) {
        imagePicker.pendingCallback = callback
        imagePicker.homeDir = homeDir
        imagePicker.openAt(startDir)
    }

    function toggle() {
        if (!showing)
            selectedIndex = 0

        showing = !showing
    }

    // -------------------------
    // PipeWire (for volume)
    // -------------------------
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    property var sink: Pipewire.defaultAudioSink
    property real pwVolume: (sink && sink.audio) ? sink.audio.volume : 0
    property bool pwMuted: (sink && sink.audio) ? sink.audio.muted : false

    // -------------------------
    // Backdrop (click-outside-to-close)
    // -------------------------
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "transparent"

        focus: root.showing
        Keys.onEscapePressed: {
            if (imagePicker.opened)
                imagePicker.dismiss()
            else
                root.hide()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }
    }

    // -------------------------
    // Nav model
    // -------------------------
    // The page area runs to the card's right edge. `rightInset` pulls a page
    // back inside the frame (28px = the card's inner padding). Pages that
    // already keep their own right margin (Sound, Network, Bluetooth) use 0.
    property var navItems: [
        { name: "System",     icon: "󰒓", page: "SystemPage", rightInset: 28 },
        { name: "Appearance", icon: "󰏘", page: "AppearancePage", rightInset: 28 },
        { name: "Top Bar",    icon: String.fromCodePoint(0xF1513), page: "TopBarPage", rightInset: 28 },
        { name: "Login Screen", icon: "󰌾", page: "LoginScreenPage", rightInset: 28 },
        { name: "Keybinds",    icon: "󰌌", page: "KeybindsPage", rightInset: 28 },
        { name: "Input",       icon: "󰍽", page: "InputPage", rightInset: 28 },
        { name: "Sound",      icon: "\uf028", page: "SoundPage", rightInset: 0 },
        { name: "Monitors",   icon: "\uf108", page: "MonitorsPage", rightInset: 28 },
        { name: "Network",    icon: "\uf1eb", page: "NetworkPage", rightInset: 0 },
        { name: "Bluetooth",  icon: "󰂯", page: "BluetoothPage", rightInset: 0 }
    ]

    property int selectedIndex: 0

    // -------------------------
    // Card
    // -------------------------
    PerspectivePanel {
        id: card
        anchors.centerIn: parent
        width: Math.min(980, root.width - 80)
        height: Math.min(640, root.height - 80)
        open: root.showing

        MouseArea {
            // swallow clicks so they don't fall through to the backdrop
            anchors.fill: parent
            onClicked: {}
        }

        // Sakura accent: translucent petals inside the frame (static, no cost
        // for any other accent).
        SakuraPetals {
            anchors.fill: parent
            z: 10
            active: Qt.colorEqual(Theme.accent, "#ff7a9d")
            tint: Theme.accent
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            radius: 6
            border.color: Theme.accent
            border.width: 1

            // faint corner glow accents, cyberpunk HUD style
            Rectangle {
                width: 40; height: 2; color: Theme.accent2
                anchors { top: parent.top; left: parent.left; margins: 14 }
            }

            Rectangle {
                width: 2; height: 40; color: Theme.accent2
                anchors { top: parent.top; left: parent.left; margins: 14 }
            }

            Rectangle {
                width: 40; height: 2; color: Theme.accent2
                anchors { bottom: parent.bottom; right: parent.right; margins: 14 }
            }

            Rectangle {
                width: 2; height: 40; color: Theme.accent2
                anchors { bottom: parent.bottom; right: parent.right; margins: 14 }
            }

            Row {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 28

                // ---------------- Sidebar ----------------
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
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.danger
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 30
                            font.bold: true
                        }

                        Text {
                            text: "SETTINGS"
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            font.letterSpacing: 4
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }

                    // ---------------- Nav buttons ----------------
                    Column {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.navItems

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: sidebar.width
                                height: 38
                                radius: Theme.radius

                                color: root.selectedIndex === index
                                    ? Theme.alpha(Theme.accent, 0.12)
                                    : "transparent"

                                border.width: root.selectedIndex === index ? 1 : 0
                                border.color: Theme.accent

                                Rectangle {
                                    visible: root.selectedIndex === index
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
                                        color: root.selectedIndex === index
                                            ? Theme.accent
                                            : Theme.textDim
                                    }

                                    Text {
                                        text: modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        color: root.selectedIndex === index
                                            ? Theme.text
                                            : Theme.textDim
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectedIndex = index
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.border
                }

                // ---------------- Page content ----------------
                Item {
                    width: parent.width - sidebar.width - 29
                    height: parent.height
                    clip: true

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        anchors.rightMargin: root.navItems[root.selectedIndex].rightInset || 0
                        source: "SettingsPages/" + root.navItems[root.selectedIndex].page + ".qml"

                        onLoaded: {
                            if (item)
                                item.hostWindow = root
                        }

                        opacity: 0
                        Component.onCompleted: opacity = 1
                        onSourceChanged: fadeIn.restart()

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animMed
                            }
                        }

                        SequentialAnimation {
                            id: fadeIn

                            PropertyAction {
                                target: pageLoader
                                property: "opacity"
                                value: 0
                            }

                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                to: 1
                                duration: Theme.animMed
                            }
                        }
                    }
                }
            }

            // In-panel image picker (modal overlay above the whole card)
            ImagePicker {
                id: imagePicker

                property var pendingCallback: null

                anchors.fill: parent
                z: 100

                onAccepted: function(path) {
                    if (pendingCallback)
                        pendingCallback(path)

                    pendingCallback = null
                }

                onClosed: backdrop.forceActiveFocus()
            }
        }
    }
}



import QtQuick
import Quickshell.Services.Pipewire
import "../"

// Settings -> Sound: the main volume, which device plays it, and a volume
// line for every app that is making sound. All of it follows PipeWire
// signals, so the page does no polling.
Item {
    id: page

    property var hostWindow: null

    // keep every node bound so names and audio levels are filled in
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property var out: Pipewire.defaultAudioSink
    readonly property bool outReady: out !== null && out.audio !== null
    readonly property real level: outReady ? out.audio.volume : 0
    readonly property bool silent: outReady ? out.audio.muted : false

    // speakers / headphones (real or virtual) and the apps playing sound
    readonly property var devices: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var players: Pipewire.nodes.values.filter(n => n.isSink && n.isStream)

    function setLevel(node, v) {
        if (node && node.audio) {
            node.audio.muted = false
            node.audio.volume = v
        }
    }

    function flipMute(node) {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted
    }

    function title(node, otherwise) {
        return node ? (node.description || node.nickname || node.name || otherwise) : otherwise
    }

    // headphones get their own icon, everything else is a speaker
    function deviceIcon(node) {
        var words = (title(node, "") + " " + (node ? node.name : "")).toLowerCase()
        return /headphone|headset|bluez/.test(words) ? 0xF02CB : 0xF04C3
    }

    function speakerIcon(v, off) {
        return off || v < 0.002 ? 0xF0581 : v < 0.34 ? 0xF057F : v < 0.67 ? 0xF0580 : 0xF057E
    }

    component Heading: Text {
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    // square (or round) button showing the speaker; click to mute
    component Speaker: Rectangle {
        id: spk

        property real amount: 0
        property bool off: false
        signal pressed()

        width: 38
        height: 38
        radius: Theme.rounded ? 12 : 0
        color: off ? Theme.tint(Theme.alert, 0.14)
            : Theme.tint(Theme.accent, spkMouse.containsMouse ? 0.20 : 0.12)

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(page.speakerIcon(spk.amount, spk.off))
            color: spk.off ? Theme.alert : Theme.accent
            font.family: Theme.glyphs
            font.pixelSize: 17
        }

        MouseArea {
            id: spkMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: spk.pressed()
        }
    }

    ScrollHint {
        flick: scroller
    }

    Flickable {
        id: scroller

        anchors.fill: parent
        contentWidth: width
        contentHeight: stack.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: stack

            width: scroller.width
            spacing: 16

            PageTitle {
                width: parent.width
                title: "SOUND"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            // ---- main volume
            Rectangle {
                width: parent.width
                height: 112
                radius: Theme.rounded ? 14 : 0
                color: Theme.card
                border.width: 1
                border.color: Theme.line

                Speaker {
                    id: mainSpeaker

                    x: 16
                    y: 16
                    amount: page.level
                    off: page.silent
                    onPressed: page.flipMute(page.out)
                }

                Text {
                    id: mainName

                    anchors.left: mainSpeaker.right
                    anchors.leftMargin: 14
                    anchors.bottom: mainSpeaker.verticalCenter
                    anchors.bottomMargin: 1
                    text: "Output volume"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                }

                Text {
                    anchors.left: mainName.left
                    anchors.right: mainPct.left
                    anchors.rightMargin: 12
                    anchors.top: mainSpeaker.verticalCenter
                    anchors.topMargin: 2
                    text: page.title(page.out, "No output device")
                    elide: Text.ElideRight
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                }

                Text {
                    id: mainPct

                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: mainSpeaker.verticalCenter
                    text: page.silent ? "MUTED" : Math.round(page.level * 100) + "%"
                    color: page.silent ? Theme.alert : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: page.silent ? 11 : 20
                    font.bold: true
                }

                LineSlider {
                    x: 18
                    y: parent.height - height - 18
                    width: parent.width - 36
                    value: page.level
                    dimmed: page.silent
                    onSliding: function(v) { page.setLevel(page.out, v) }
                }
            }

            // ---- where the sound goes
            Heading {
                text: "OUTPUT DEVICE"
            }

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: page.devices

                    delegate: Rectangle {
                        id: dev

                        required property var modelData
                        readonly property bool inUse: page.out !== null && page.out.id === modelData.id

                        width: parent.width
                        height: 48
                        radius: Theme.rounded ? 10 : 0
                        color: inUse ? Theme.tint(Theme.accent, 0.13)
                            : devMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : Theme.card
                        border.width: 1
                        border.color: inUse ? Theme.accent
                            : devMouse.containsMouse ? Theme.lineHot : Theme.line

                        Behavior on color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Text {
                            id: devIcon

                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(page.deviceIcon(dev.modelData))
                            color: dev.inUse ? Theme.accent : Theme.inkSoft
                            font.family: Theme.glyphs
                            font.pixelSize: 16
                        }

                        Text {
                            anchors.left: devIcon.right
                            anchors.leftMargin: 14
                            anchors.right: devTick.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.title(dev.modelData, "Unknown output")
                            elide: Text.ElideRight
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }

                        Text {
                            id: devTick

                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: dev.inUse ? String.fromCodePoint(0xF012C) : ""
                            color: Theme.accent
                            font.family: Theme.glyphs
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: devMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!dev.inUse)
                                    Pipewire.preferredDefaultAudioSink = dev.modelData
                            }
                        }
                    }
                }

                Text {
                    visible: page.devices.length === 0
                    text: "No audio outputs found."
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }

            // ---- apps making sound
            Row {
                spacing: 8

                Heading {
                    text: "APPS"
                }

                Rectangle {
                    visible: page.players.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: playerCount.implicitWidth + 12
                    height: 16
                    radius: Theme.rounded ? 8 : 0
                    color: Theme.tint(Theme.accent, 0.14)

                    Text {
                        id: playerCount

                        anchors.centerIn: parent
                        text: String(page.players.length)
                        color: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: page.players

                    delegate: Rectangle {
                        id: player

                        required property var modelData
                        readonly property bool hasAudio: modelData !== null && modelData.audio !== null
                        readonly property bool quiet: hasAudio && modelData.audio.muted
                        readonly property real amount: hasAudio ? modelData.audio.volume : 0

                        width: parent.width
                        height: 64
                        radius: Theme.rounded ? 12 : 0
                        color: Theme.card
                        border.width: 1
                        border.color: quiet ? Theme.tint(Theme.alert, 0.45) : Theme.line

                        Speaker {
                            id: playerSpeaker

                            x: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            amount: player.amount
                            off: player.quiet
                            onPressed: page.flipMute(player.modelData)
                        }

                        Text {
                            anchors.left: playerSpeaker.right
                            anchors.leftMargin: 14
                            anchors.right: playerPct.left
                            anchors.rightMargin: 12
                            y: 14
                            text: page.title(player.modelData, "Unknown app")
                            elide: Text.ElideRight
                            color: player.quiet ? Theme.inkSoft : Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }

                        Text {
                            id: playerPct

                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            y: 14
                            text: player.quiet ? "MUTED" : Math.round(player.amount * 100) + "%"
                            color: player.quiet ? Theme.alert : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }

                        LineSlider {
                            anchors.left: playerSpeaker.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            y: parent.height - height - 12
                            value: player.amount
                            dimmed: player.quiet
                            onSliding: function(v) { page.setLevel(player.modelData, v) }
                        }
                    }
                }

                Text {
                    visible: page.players.length === 0
                    text: "No app is playing audio right now."
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }
        }
    }
}

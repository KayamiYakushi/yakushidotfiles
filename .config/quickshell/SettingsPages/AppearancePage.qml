import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page

    property string homeDir: ""
    property real launcherOpacity: 0.8
    property real topBarOpacity: 0.5
    property string launcherStatus: ""
    property string topBarStatus: ""

    property var presets: [
        { name: "MONO",        accent: "#ffffff" },
        { name: "YAKUSHI RED", accent: "#ff003c" },
        { name: "SOFT ROSE",   accent: "#ff7a9d" }
    ]

    function launcherHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-appearancectl.py"
    }

    function topBarHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-waybar-opacityctl.py"
    }

    function loadLauncherOpacity() {
        if (homeDir === "" || launcherGet.running)
            return

        launcherGet.command = [
            "python3",
            launcherHelperPath(),
            "get"
        ]
        launcherGet.running = true
    }

    function saveLauncherOpacity(value) {
        if (launcherSet.running)
            return

        launcherSet.command = [
            "python3",
            launcherHelperPath(),
            "set",
            value.toFixed(3)
        ]
        launcherSet.running = true
    }

    function loadTopBarOpacity() {
        if (homeDir === "" || topBarGet.running)
            return

        topBarGet.command = [
            "python3",
            topBarHelperPath(),
            "get"
        ]
        topBarGet.running = true
    }

    function saveTopBarOpacity(value) {
        if (topBarSet.running)
            return

        topBarSet.command = [
            "python3",
            topBarHelperPath(),
            "set",
            value.toFixed(3)
        ]
        topBarSet.running = true
    }

    Process {
        id: homeProc
        command: ["sh", "-c", "printf '%s' \"$HOME\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.homeDir = text.trim()
                page.loadLauncherOpacity()
                page.loadTopBarOpacity()
            }
        }
    }

    Process {
        id: launcherGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.launcherOpacity = data.opacity
                        page.launcherStatus = ""
                    } else {
                        page.launcherStatus = data.message
                    }
                } catch (e) {
                    page.launcherStatus = "Could not read app launcher opacity."
                }
            }
        }
    }

    Process {
        id: launcherSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.launcherOpacity = data.opacity
                        page.launcherStatus = data.message
                    } else {
                        page.launcherStatus = data.message
                    }
                } catch (e) {
                    page.launcherStatus = "Could not save app launcher opacity."
                }
            }
        }
    }

    Process {
        id: topBarGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.topBarOpacity = data.opacity
                        page.topBarStatus = ""
                    } else {
                        page.topBarStatus = data.message
                    }
                } catch (e) {
                    page.topBarStatus = "Could not read top bar opacity."
                }
            }
        }
    }

    Process {
        id: topBarSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.topBarOpacity = data.opacity
                        page.topBarStatus = data.message
                    } else {
                        page.topBarStatus = data.message
                    }
                } catch (e) {
                    page.topBarStatus = "Could not save top bar opacity."
                }
            }
        }
    }

    Timer {
        id: launcherSaveDebounce
        interval: 120
        repeat: false
        onTriggered: page.saveLauncherOpacity(page.launcherOpacity)
    }

    Timer {
        id: topBarSaveDebounce
        interval: 120
        repeat: false
        onTriggered: page.saveTopBarOpacity(page.topBarOpacity)
    }

    Column {
        anchors.fill: parent
        spacing: 20

        Text {
            text: "APPEARANCE"
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

        Text {
            text: "ACCENT"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Row {
            width: parent.width
            spacing: 12

            Repeater {
                model: page.presets

                delegate: Rectangle {
                    required property var modelData

                    width: 150
                    height: 72
                    radius: Theme.radius
                    color: Theme.bgCard
                    border.width: 1
                    border.color: Theme.accent === modelData.accent
                        ? modelData.accent
                        : Theme.border

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            color: modelData.accent
                            border.width: 1
                            border.color: Theme.textDim
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.accent = modelData.accent
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        Text {
            text: "GLASS"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Slider {
            width: parent.width
            label: "PANEL OPACITY  "
                + Math.round(Theme.panelOpacity * 100)
                + "%"
            icon: "◐"
            accentColor: Theme.accent
            value: (Theme.panelOpacity - 0.40) / 0.60

            onMoved: function(v) {
                Theme.panelOpacity = 0.40 + (v * 0.60)
            }

            onCommitted: function(v) {
                Theme.panelOpacity = 0.40 + (v * 0.60)
            }
        }

        Slider {
            width: parent.width
            label: "App launcher opacity  "
                + Math.round(page.launcherOpacity * 100)
                + "%"
            icon: "󰀻"
            accentColor: Theme.accent
            value: page.launcherOpacity

            onMoved: function(v) {
                page.launcherOpacity = v
                launcherSaveDebounce.restart()
            }

            onCommitted: function(v) {
                page.launcherOpacity = v
                launcherSaveDebounce.stop()
                page.saveLauncherOpacity(v)
            }
        }

        Slider {
            width: parent.width
            label: "Top bar opacity  "
                + Math.round(page.topBarOpacity * 100)
                + "%"
            icon: "󰨇"
            accentColor: Theme.accent
            value: page.topBarOpacity

            onMoved: function(v) {
                page.topBarOpacity = v
                topBarSaveDebounce.restart()
            }

            onCommitted: function(v) {
                page.topBarOpacity = v
                topBarSaveDebounce.stop()
                page.saveTopBarOpacity(v)
            }
        }

        Text {
            visible: page.launcherStatus !== ""
                || page.topBarStatus !== ""
            width: parent.width
            text: page.topBarStatus !== ""
                ? page.topBarStatus
                : page.launcherStatus
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}

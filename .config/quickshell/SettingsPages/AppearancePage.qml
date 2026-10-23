import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    property string homeDir: ""
    property real launcherOpacity: 0.8
    property real topBarOpacity: 0.5
    property string launcherStatus: ""
    property string topBarStatus: ""
    property bool clockSeconds: false

    property var presets: [
        { name: "MONO",        accent: "#ffffff" },
        { name: "RED",         accent: "#ff003c" },
        { name: "SAKURA",      accent: "#ff7a9d" }
    ]

    function launcherHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-appearancectl.py"
    }

    function topBarHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-waybar-opacityctl.py"
    }

    function clockHelperPath() {
        return homeDir + "/.config/hypr/scripts/yakushi-clockctl.py"
    }

    function loadClockSeconds() {
        if (homeDir === "" || clockGet.running)
            return

        clockGet.command = ["python3", clockHelperPath(), "get"]
        clockGet.running = true
    }

    function toggleClockSeconds() {
        if (homeDir === "" || clockSet.running)
            return

        clockSet.command = [
            "python3",
            clockHelperPath(),
            "set",
            page.clockSeconds ? "off" : "on"
        ]
        clockSet.running = true
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
                page.loadClockSeconds()
            }
        }
    }

    Process {
        id: clockGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok)
                        page.clockSeconds = data.seconds === true
                    else
                        page.topBarStatus = data.message
                } catch (e) {
                    page.topBarStatus = "Could not read clock settings."
                }
            }
        }
    }

    Process {
        id: clockSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok)
                        page.clockSeconds = data.seconds === true

                    page.topBarStatus = data.message
                } catch (e) {
                    page.topBarStatus = "Could not update the clock."
                }
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

        // The page area runs to the card's edge; keep a 28px inner margin so
        // dividers, presets and the switch stay inside the panel.
        anchors.rightMargin: 28
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
                    border.color: Qt.colorEqual(Theme.accent, modelData.accent)
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

        // Same header language as the sliders: accent icon, label, control.
        Item {
            id: secondsRow

            width: parent.width
            height: 28

            Text {
                id: secondsIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: "󰥔"
                color: Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 15
            }

            Text {
                anchors.left: secondsIcon.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Show seconds"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 1
            }

            Text {
                anchors.right: secondsTrack.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: page.clockSeconds ? "ON" : "OFF"
                color: page.clockSeconds ? Theme.accent : Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast }
                }
            }

            // Square-cornered switch, matching the slider track and cards.
            Rectangle {
                id: secondsTrack

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 16
                radius: Theme.radius
                color: page.clockSeconds
                    ? Theme.alpha(Theme.accent, 0.18)
                    : Theme.trackBg
                border.width: 1
                border.color: page.clockSeconds
                    ? Theme.accent
                    : (secondsMouse.containsMouse ? Theme.borderAccent : Theme.border)

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast }
                }

                Behavior on border.color {
                    ColorAnimation { duration: Theme.animFast }
                }

                Rectangle {
                    width: 10
                    height: 10
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: page.clockSeconds ? parent.width - width - 3 : 3
                    color: page.clockSeconds ? Theme.accent : Theme.textDim

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.animFast
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }
                }
            }

            MouseArea {
                id: secondsMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.toggleClockSeconds()
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

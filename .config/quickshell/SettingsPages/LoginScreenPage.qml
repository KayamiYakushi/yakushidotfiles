import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    readonly property string homeDir: Quickshell.env("HOME") || ""
    property url previewSource: ""
    property bool hasBackground: false
    property string statusMessage: ""
    property bool setAuthorizationHeld: false
    property bool resetAuthorizationHeld: false

    function helperPath() {
        return homeDir + "/.config/quickshell/scripts/yakushi-sddmctl.py"
    }

    function loadState() {
        if (homeDir === "" || statusProc.running)
            return

        statusProc.command = ["python3", helperPath(), "status"]
        statusProc.running = true
    }

    function setBackground(url) {
        if (setProc.running)
            return

        statusMessage = "Waiting for authorization..."

        if (hostWindow && !setAuthorizationHeld) {
            hostWindow.beginExternalDialog()
            setAuthorizationHeld = true
        }

        setProc.command = ["python3", helperPath(), "set", url]
        setProc.running = true
    }

    function resetBackground() {
        if (resetProc.running)
            return

        statusMessage = "Waiting for authorization..."

        if (hostWindow && !resetAuthorizationHeld) {
            hostWindow.beginExternalDialog()
            resetAuthorizationHeld = true
        }

        resetProc.command = ["python3", helperPath(), "reset"]
        resetProc.running = true
    }

    // first load
    Component.onCompleted: {
        page.loadState()
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.hasBackground = data.background === true
                    page.previewSource = data.preview || ""
                    page.statusMessage = data.message || ""
                } catch (e) {
                    page.statusMessage = "Could not read login screen state."
                }
            }
        }
    }

    Process {
        id: setProc

        onRunningChanged: {
            if (!running && page.setAuthorizationHeld) {
                if (page.hostWindow)
                    page.hostWindow.endExternalDialog()
                page.setAuthorizationHeld = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.hasBackground = true
                        page.statusMessage = data.message || "Login background updated."
                    } else {
                        page.statusMessage = data.message || "Could not update login background."
                    }
                } catch (e) {
                    page.statusMessage = "Could not update login background."
                }
            }
        }
    }

    Process {
        id: resetProc

        onRunningChanged: {
            if (!running && page.resetAuthorizationHeld) {
                if (page.hostWindow)
                    page.hostWindow.endExternalDialog()
                page.resetAuthorizationHeld = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.ok) {
                        page.hasBackground = false
                        page.previewSource = ""
                        page.statusMessage = data.message || "Login background reset."
                    } else {
                        page.statusMessage = data.message || "Could not reset login background."
                    }
                } catch (e) {
                    page.statusMessage = "Could not reset login background."
                }
            }
        }
    }

    function chooseBackground() {
        if (!hostWindow)
            return

        hostWindow.openImagePicker(
            homeDir,
            homeDir + "/Pictures",
            function(path) {
                page.previewSource = "file://" + path.split("/").map(encodeURIComponent).join("/")
                page.setBackground(path)
            }
        )
    }

    Column {
        anchors.fill: parent
        spacing: 18

        PageTitle {
            width: parent.width
            title: "LOGIN SCREEN"
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
        }

        Text {
            text: "SDDM"
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Rectangle {
            width: parent.width
            height: 290
            radius: Theme.corner
            color: "#080808"
            border.width: 1
            border.color: Theme.line
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#181818" }
                    GradientStop { position: 1.0; color: "#030303" }
                }
            }

            Image {
                anchors.fill: parent
                source: page.previewSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: source.toString() !== ""
            }

            Rectangle {
                anchors.fill: parent
                color: "#52000000"
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                spacing: 6

                Text {
                    text: "薬"
                    color: "#ff003c"
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 34
                    font.bold: true
                }

                Text {
                    text: page.hasBackground
                        ? "CUSTOM LOGIN BACKGROUND"
                        : "DEFAULT DARK LOGIN"
                    color: "#b0b0b0"
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }
        }

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: 200
                height: 38
                radius: Theme.corner
                color: Theme.tint(Theme.accent, 0.10)
                border.width: 1
                border.color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: "CHOOSE BACKGROUND"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.chooseBackground()
                }
            }

            Rectangle {
                width: 100
                height: 38
                radius: Theme.corner
                color: "transparent"
                border.width: 1
                border.color: Theme.line
                opacity: page.hasBackground ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "RESET"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: page.hasBackground
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: page.resetBackground()
                }
            }
        }

        Text {
            width: parent.width
            text: page.statusMessage !== ""
                ? page.statusMessage
                : "Changes appear on the next SDDM login."
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: "The selected image is copied to the system SDDM theme after Polkit authorization. Your source file stays untouched."
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}

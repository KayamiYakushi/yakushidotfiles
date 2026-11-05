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

    function helperPath() {
        return homeDir + "/.config/quickshell/scripts/yakushi-sddmctl.py"
    }

    function loadState() {
        if (homeDir === "" || statusProc.running)
            return

        statusProc.command = ["python3", helperPath(), "status"]
        statusProc.running = true
    }

    // Changing the system's login screen needs your password: it is asked
    // right here (no dialog that could open behind Settings) and goes to
    // sudo through a pipe.
    property var pendingArgs: []       // ["set", <image>] or ["reset"], waiting for the password
    property var lastArgs: []
    property string secret: ""

    function ask(args) {
        if (rootProc.running)
            return
        pendingArgs = args
        statusMessage = ""
        passwordAsk.error = ""
        Qt.callLater(passwordAsk.open)
    }

    function runRoot(args, password) {
        lastArgs = args
        secret = password
        statusMessage = args[0] === "set" ? "Preparing the picture..." : "Resetting..."
        rootProc.stdinEnabled = true
        rootProc.command = ["python3", helperPath(), "--password-stdin"].concat(args)
        rootProc.running = true
    }

    function setBackground(path) {
        ask(["set", path])
    }

    function resetBackground() {
        ask(["reset"])
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
                    if (page.statusMessage === "")
                        page.statusMessage = data.message || ""
                } catch (e) {
                    page.statusMessage = "Could not read login screen state."
                }
            }
        }
    }

    Process {
        id: rootProc

        onStarted: {
            if (stdinEnabled) {
                rootProc.write(page.secret + "\n")
                page.secret = ""
                stdinEnabled = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var setting = page.lastArgs[0] === "set"
                try {
                    var data = JSON.parse(text)

                    if (data.wrongPassword) {
                        page.pendingArgs = page.lastArgs
                        page.statusMessage = ""
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    page.statusMessage = data.message
                        || (data.ok ? "Done." : setting ? "Could not update login background." : "Could not reset login background.")
                    if (data.ok) {
                        page.hasBackground = setting
                        if (!setting)
                            page.previewSource = ""
                        return
                    }
                } catch (e) {
                    page.statusMessage = setting ? "Could not update login background." : "Could not reset login background."
                }
                page.loadState()           // show what the login screen really has
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
            textFormat: Text.PlainText
            text: "SDDM"
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Rectangle {
            width: parent.width
            height: 290
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
                    textFormat: Text.PlainText
                    text: "薬"
                    color: "#ff003c"
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 34
                    font.bold: true
                }

                Text {
                    textFormat: Text.PlainText
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
                color: Theme.tint(Theme.accent, 0.10)
                border.width: 1
                border.color: Theme.accent

                Text {
                    textFormat: Text.PlainText
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
                color: "transparent"
                border.width: 1
                border.color: Theme.line
                opacity: page.hasBackground ? 1.0 : 0.45

                Text {
                    textFormat: Text.PlainText
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

        PasswordRow {
            id: passwordAsk

            width: parent.width
            visible: page.pendingArgs.length > 0
            label: page.pendingArgs[0] === "reset" ? "Your password, to reset the login background"
                                                    : "Your password, to change the login background"
            action: page.pendingArgs[0] === "reset" ? "RESET" : "SET"
            onAccepted: function(password) {
                var args = page.pendingArgs
                page.pendingArgs = []
                page.runRoot(args, password)
            }
            onCanceled: {
                page.pendingArgs = []
                page.statusMessage = "Cancelled. Nothing was changed."
                page.loadState()
            }
        }

        Text {
            textFormat: Text.PlainText
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
            textFormat: Text.PlainText
            width: parent.width
            text: "The picture is made into a clean PNG as you (never opened as root), then copied into the system SDDM theme with your password. Your file stays untouched."
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}

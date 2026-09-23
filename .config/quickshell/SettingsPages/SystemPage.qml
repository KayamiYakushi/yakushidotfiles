import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls as QQC
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    property string homeDir: ""
    property url profileSource: ""

    property string hostname: "..."
    property string uptime: "..."
    property string os: "..."

    property string cpu: "Loading..."
    property string gpu: "Loading..."
    property string memory: "Loading..."
    property string storage: "Loading..."

    // ------------------------------------------------------------
    // GLOBAL TEXT SIZES
    // ------------------------------------------------------------

    // Hardware section labels: CPU, GPU, MEMORY, STORAGE
    property int hardwareLabelSize: 12

    // Hardware values: CPU/GPU names, memory usage, storage usage
    property int hardwareTextSize: 12

    // ------------------------------------------------------------
    // HOME DIRECTORY
    // ------------------------------------------------------------

    Process {
        id: pHome

        command: [
            "sh",
            "-c",
            "printf '%s' \"$HOME\""
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.homeDir = text.trim()

                if (page.homeDir !== "")
                    page.profileSource = "file://" + page.homeDir + "/.config/quickshell/assets/system-profile"
            }
        }
    }

    // ------------------------------------------------------------
    // SYSTEM IMAGE
    // ------------------------------------------------------------

    FileDialog {
        id: profilePicker

        options: FileDialog.DontUseNativeDialog
        parentWindow: page.hostWindow
        popupType: QQC.Popup.Window
        // Temporarily lower the layer-shell Settings surface so the
        // native/system file chooser can stack above it and receive input.
        onVisibleChanged: {
            if (!page.hostWindow)
                return

            if (visible)
                page.hostWindow.beginExternalDialog()
            else
                page.hostWindow.endExternalDialog()
        }

        title: "Choose System Image"

        nameFilters: [
            "Images (*.png *.jpg *.jpeg *.webp)",
            "All files (*)"
        ]

        onAccepted: {
            var selectedUrl = selectedFile.toString()
            var localPath = decodeURIComponent(selectedUrl.replace("file://", ""))

            page.profileSource = selectedFile

            pSaveProfile.command = [
                "python3",
                page.homeDir + "/.config/quickshell/scripts/yakushi-profile-image.py",
                localPath
            ]

            pSaveProfile.running = true
        }
    }

    Process {
        id: pSaveProfile
    }

    // ------------------------------------------------------------
    // SYSTEM INFO
    // ------------------------------------------------------------

    Process {
        id: pHost

        command: [
            "sh",
            "-c",
            "hostnamectl --static 2>/dev/null || cat /etc/hostname"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.hostname = text.trim()
        }
    }

    Process {
        id: pUptime

        command: [
            "uptime",
            "-p"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.uptime = text.trim()
        }
    }

    Process {
        id: pOs

        command: [
            "sh",
            "-c",
            "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.os = text.trim()
        }
    }

    // ------------------------------------------------------------
    // HARDWARE INFO
    // ------------------------------------------------------------

    Process {
        id: pCpu

        command: [
            "sh",
            "-c",
            "awk -F: '/model name/ {gsub(/^ +/, \"\", $2); print $2; exit}' /proc/cpuinfo"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.cpu = text.trim()
        }
    }

    Process {
        id: pGpu

        command: [
            "sh",
            "-c",
            "lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | sed -E 's/.*: //; s/ \\(rev.*\\)//' | head -1"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.gpu = text.trim()

                if (page.gpu === "")
                    page.gpu = "Unknown"
            }
        }
    }

    Process {
        id: pMemory

        command: [
            "sh",
            "-c",
            "free -h | awk '/^Mem:/ {print $3 \" / \" $2}'"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.memory = text.trim()
        }
    }

    Process {
        id: pStorage

        command: [
            "sh",
            "-c",
            "df -h / | awk 'NR==2 {print $3 \" / \" $2 \" (\" $5 \")\"}'"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: page.storage = text.trim()
        }
    }

    // ------------------------------------------------------------
    // REFRESH
    // ------------------------------------------------------------

    Timer {
        interval: 5000
        running: true
        repeat: true

        onTriggered: {
            pUptime.running = true
            pMemory.running = true
            pStorage.running = true
        }
    }

    // ------------------------------------------------------------
    // MAIN CONTENT
    // ------------------------------------------------------------

    Column {
        anchors.fill: parent
        spacing: 20

        // --------------------------------------------------------
        // TITLE
        // --------------------------------------------------------

        Text {
            text: "SYSTEM"

            color: Theme.text

            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            font.bold: false
            font.letterSpacing: 3
        }

        // --------------------------------------------------------
        // DIVIDER
        // --------------------------------------------------------

        Rectangle {
            width: parent.width
            height: 1

            color: Theme.border
        }

        // --------------------------------------------------------
        // PROFILE + SYSTEM INFORMATION
        // --------------------------------------------------------

        Row {
            width: parent.width
            height: 150

            spacing: 24

            Rectangle {
                id: profileFrame

                width: 150
                height: 150

                color: Theme.alpha(Theme.bgCard, 0.72)

                radius: 4

                border.width: profileMouse.containsMouse ? 1 : 0
                border.color: Theme.accent

                clip: true

                Image {
                    id: profileImage

                    anchors.fill: parent
                    anchors.margins: 5

                    source: page.profileSource

                    fillMode: Image.PreserveAspectCrop

                    smooth: true
                    mipmap: true
                    asynchronous: true
                    cache: false
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    visible: profileImage.status !== Image.Ready

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "󰋩"

                        color: Theme.textDim

                        font.family: Theme.iconFont
                        font.pixelSize: 22
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "ADD IMAGE"

                        color: Theme.textDim

                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    height: 25

                    visible: profileImage.status === Image.Ready && profileMouse.containsMouse

                    color: Theme.alpha("#000000", 0.72)

                    Text {
                        anchors.centerIn: parent

                        text: "CHANGE IMAGE"

                        color: Theme.text

                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }

                MouseArea {
                    id: profileMouse

                    anchors.fill: parent

                    hoverEnabled: true

                    onClicked: profilePicker.open()
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                spacing: 14

                Column {
                    spacing: 3

                    Text {
                        text: "󰒋  HOSTNAME"

                        color: Theme.accent

                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Text {
                        text: page.hostname

                        color: Theme.text

                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }

                Column {
                    spacing: 3

                    Text {
                        text: "󰣇  OS"

                        color: Theme.accent

                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Text {
                        text: page.os

                        color: Theme.text

                        font.family: Theme.fontFamily
                        font.pixelSize: 13

                        elide: Text.ElideRight
                        width: 500
                    }
                }

                Column {
                    spacing: 3

                    Text {
                        text: "󰔛  UPTIME"

                        color: Theme.accent

                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Text {
                        text: page.uptime

                        color: Theme.text

                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
            }
        }

        // --------------------------------------------------------
        // HARDWARE INFORMATION — SINGLE COLUMN
        // --------------------------------------------------------

        Column {
            width: parent.width
            spacing: 40

            // ----------------------------------------------------
            // CPU
            // ----------------------------------------------------

            Column {
                width: parent.width
                spacing: 10

                Text {
                    text: "󰍛  CPU"

                    color: Theme.accent

                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: page.hardwareLabelSize
                    font.letterSpacing: 2
                }

                Text {
                    text: page.cpu

                    color: Theme.text

                    font.family: Theme.fontFamily
                    font.pixelSize: page.hardwareTextSize

                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // ----------------------------------------------------
            // GPU
            // ----------------------------------------------------

            Column {
                width: parent.width
                spacing: 10

                Text {
                    text: "󰢮  GPU"

                    color: Theme.accent

                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: page.hardwareLabelSize
                    font.letterSpacing: 2
                }

                Text {
                    text: page.gpu

                    color: Theme.text

                    font.family: Theme.fontFamily
                    font.pixelSize: page.hardwareTextSize

                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // ----------------------------------------------------
            // MEMORY
            // ----------------------------------------------------

            Column {
                width: parent.width
                spacing: 10

                Text {
                    text: "󰘚  MEMORY"

                    color: Theme.accent

                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: page.hardwareLabelSize
                    font.letterSpacing: 2
                }

                Text {
                    text: page.memory

                    color: Theme.text

                    font.family: Theme.fontFamily
                    font.pixelSize: page.hardwareTextSize
                }
            }

            // ----------------------------------------------------
            // STORAGE
            // ----------------------------------------------------

            Column {
                width: parent.width
                spacing: 10

                Text {
                    text: "󰋊  STORAGE"

                    color: Theme.accent

                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: page.hardwareLabelSize
                    font.letterSpacing: 2
                }

                Text {
                    text: page.storage

                    color: Theme.text

                    font.family: Theme.fontFamily
                    font.pixelSize: page.hardwareTextSize
                }
            }
        }
    }
}

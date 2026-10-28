import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#050505"

    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property date now: new Date()
    property bool loginFailed: false

    function doLogin() {
        root.loginFailed = false
        message.text = "AUTHENTICATING..."
        sddm.login(userEntry.text, passwordEntry.text, root.sessionIndex)
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl(config.background)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    Rectangle {
        anchors.fill: parent
        color: "#66000000"
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 64
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64
        spacing: 6

        Text {
            text: Qt.formatTime(root.now, "HH:mm")
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 66
            font.bold: true
        }

        Text {
            text: Qt.formatDate(root.now, "dddd · dd MMMM")
            color: "#b0b0b0"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
        }
    }

    Rectangle {
        id: card
        width: 380
        height: 400
        radius: 26
        color: "#E60A0A0A"
        border.width: 1
        border.color: "#1FFFFFFF"
        anchors.right: parent.right
        anchors.rightMargin: 72
        anchors.verticalCenter: parent.verticalCenter

        Column {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 15

            Row {
                spacing: 12

                Text {
                    text: "薬"
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#ff003c"
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 26
                    font.bold: true
                }

                Text {
                    text: "LOGIN"
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 17
                    font.bold: true
                    font.letterSpacing: 3
                }
            }

            Item { width: 1; height: 5 }

            Text {
                text: "WELCOME BACK"
                color: "#e8e8e8"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 2
            }

            Rectangle {
                width: parent.width
                height: 48
                radius: 14
                color: "#12FFFFFF"
                border.width: 1
                border.color: userEntry.activeFocus ? "#70FFFFFF" : "#24FFFFFF"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰀄"
                    color: userEntry.activeFocus ? "#ffffff" : "#777777"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                }

                Text {
                    visible: userEntry.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: "USERNAME"
                    color: "#777777"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                TextInput {
                    id: userEntry
                    anchors.fill: parent
                    anchors.leftMargin: 44
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    text: userModel.lastUser
                    color: "#ffffff"
                    selectionColor: "#55FFFFFF"
                    selectedTextColor: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            passwordEntry.forceActiveFocus()
                            event.accepted = true
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 48
                radius: 14
                color: "#12FFFFFF"
                border.width: 1
                border.color: passwordEntry.activeFocus ? "#70FFFFFF" : "#24FFFFFF"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰌾"
                    color: passwordEntry.activeFocus ? "#ffffff" : "#777777"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                }

                Text {
                    visible: passwordEntry.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PASSWORD"
                    color: "#777777"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                TextInput {
                    id: passwordEntry
                    anchors.fill: parent
                    anchors.leftMargin: 44
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: "#ffffff"
                    selectionColor: "#55FFFFFF"
                    selectedTextColor: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.doLogin()
                            event.accepted = true
                        }
                    }
                }
            }

            Text {
                id: message
                width: parent.width
                height: 14
                text: ""
                color: root.loginFailed ? "#ff5a70" : "#888888"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }

            Rectangle {
                width: parent.width
                height: 46
                radius: 23
                color: signInMouse.containsMouse ? "#e6e6e6" : "#ffffff"

                Text {
                    anchors.centerIn: parent
                    text: "SIGN IN"
                    color: "#080808"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }

                MouseArea {
                    id: signInMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.doLogin()
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Repeater {
                    model: [
                        { label: "RESTART", glyph: "󰜉", action: "reboot" },
                        { label: "SHUT DOWN", glyph: "󰐥", action: "poweroff" }
                    ]

                    delegate: Rectangle {
                        id: powerPill

                        required property var modelData
                        readonly property bool allowed: modelData.action === "reboot" ? sddm.canReboot : sddm.canPowerOff

                        width: pillRow.implicitWidth + 26
                        height: 32
                        radius: 16
                        opacity: allowed ? 1 : 0.4
                        color: pillMouse.containsMouse ? "#1FFFFFFF" : "transparent"
                        border.width: 1
                        border.color: "#24FFFFFF"

                        Row {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: powerPill.modelData.glyph
                                color: "#bbbbbb"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: powerPill.modelData.label
                                color: "#bbbbbb"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: powerPill.allowed
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerPill.modelData.action === "reboot" ? sddm.reboot() : sddm.powerOff()
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.loginFailed = true
            message.text = "AUTHENTICATION FAILED"
            passwordEntry.text = ""
            passwordEntry.forceActiveFocus()
        }

        function onInformationMessage(text) {
            message.text = text
        }
    }

    Component.onCompleted: {
        if (userEntry.text.length > 0)
            passwordEntry.forceActiveFocus()
        else
            userEntry.forceActiveFocus()
    }
}

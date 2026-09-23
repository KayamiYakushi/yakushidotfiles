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
        height: 390
        radius: 18
        color: "#E6101010"
        border.width: 1
        border.color: "#38FFFFFF"
        anchors.right: parent.right
        anchors.rightMargin: 72
        anchors.verticalCenter: parent.verticalCenter

        Column {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 15

            Row {
                spacing: 10

                Text {
                    text: "薬"
                    color: "#ff003c"
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 26
                    font.bold: true
                }

                Column {
                    spacing: 1

                    Text {
                        text: "YAKUSHI"
                        color: "#ffffff"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17
                        font.bold: true
                        font.letterSpacing: 3
                    }

                    Text {
                        text: "LOGIN"
                        color: "#777777"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
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
                height: 46
                radius: 8
                color: "#16FFFFFF"
                border.width: 1
                border.color: userEntry.activeFocus ? "#70FFFFFF" : "#24FFFFFF"

                Text {
                    visible: userEntry.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 14
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
                    anchors.leftMargin: 14
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
                height: 46
                radius: 8
                color: "#16FFFFFF"
                border.width: 1
                border.color: passwordEntry.activeFocus ? "#70FFFFFF" : "#24FFFFFF"

                Text {
                    visible: passwordEntry.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 14
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
                    anchors.leftMargin: 14
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
                height: 44
                radius: 8
                color: "#ffffff"

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
                    anchors.fill: parent
                    onClicked: root.doLogin()
                }
            }

            Row {
                spacing: 24

                Text {
                    text: "REBOOT"
                    color: "#888888"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: sddm.canReboot
                        onClicked: sddm.reboot()
                    }
                }

                Text {
                    text: "POWER OFF"
                    color: "#888888"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: sddm.canPowerOff
                        onClicked: sddm.powerOff()
                    }
                }
            }
        }
    }

    Timer {
        interval: 1000
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

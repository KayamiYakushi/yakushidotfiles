import QtQuick
import "../"

// Your password, asked inside Settings (so no dialog opens behind it).
// It goes to sudo through a pipe and is cleared from here right away.
Rectangle {
    id: row

    property string label: "PASSWORD"
    property string action: "OK"
    property string error: ""

    signal accepted(string password)
    signal canceled()

    function open() {
        field.text = ""
        field.forceActiveFocus()
    }

    function send() {
        if (field.text === "")
            return
        var pw = field.text
        field.text = ""
        row.accepted(pw)
    }

    height: 36
    color: Theme.tint(Theme.ink, 0.03)
    border.width: 1
    border.color: row.error !== "" ? Theme.alert : field.activeFocus ? Theme.accent : Theme.line

    Text {
        id: lock

        textFormat: Text.PlainText
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint(0xF033E)
        color: row.error !== "" ? Theme.alert : Theme.accent
        font.family: Theme.glyphs
        font.pixelSize: 13
    }

    TextInput {
        id: field

        anchors.left: lock.right
        anchors.leftMargin: 10
        anchors.right: buttons.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        echoMode: TextInput.Password
        passwordCharacter: "•"
        clip: true
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
        Keys.onReturnPressed: row.send()
        Keys.onEnterPressed: row.send()
        Keys.onEscapePressed: row.canceled()

        Text {
            textFormat: Text.PlainText
            visible: field.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: row.error !== "" ? row.error : row.label
            color: row.error !== "" ? Theme.alert : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 11
        }
    }

    Row {
        id: buttons

        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: [["cancel", "CANCEL"], ["ok", row.action]]

            delegate: Rectangle {
                id: b

                required property var modelData

                width: bText.implicitWidth + 20
                height: 28
                color: modelData[0] === "ok" ? Theme.tint(Theme.alert, bMouse.containsMouse ? 0.3 : 0.18)
                    : bMouse.containsMouse ? Theme.tint(Theme.ink, 0.08) : "transparent"
                border.width: 1
                border.color: modelData[0] === "ok" ? Theme.alert : Theme.line

                Text {
                    id: bText

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: b.modelData[1]
                    color: b.modelData[0] === "ok" ? Theme.alert : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: bMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: b.modelData[0] === "ok" ? row.send() : row.canceled()
                }
            }
        }
    }
}

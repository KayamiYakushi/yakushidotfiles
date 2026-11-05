import QtQuick

// Page heading used at the top of each Settings page: an accent block, the
// title in heavy caps and a hard rule.
Item {
    id: heading

    property string title: ""

    implicitHeight: 26

    // accent block, title, rule
    Rectangle {
        id: block

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 18
        color: Theme.accent
    }

    Text {
        id: label

        textFormat: Text.PlainText
        anchors.left: block.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: heading.title
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 20
        font.bold: true
        font.letterSpacing: 5
    }

    Text {
        id: slashes

        textFormat: Text.PlainText
        anchors.left: label.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "//"
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 12
    }

    Rectangle {
        anchors.left: slashes.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.tint(Theme.ink, 0.10)

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 7
            color: Theme.tint(Theme.ink, 0.35)
        }
    }
}

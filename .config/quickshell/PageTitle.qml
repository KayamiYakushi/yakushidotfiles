import QtQuick

// Page heading used at the top of each Settings page.
//  sharp:   an accent block, the title in heavy caps and a hard rule
//  rounded: the plain spaced title of the rounded style
Item {
    id: heading

    property string title: ""

    implicitHeight: 26

    // rounded style
    Text {
        visible: Theme.rounded
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: heading.title
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 18
        font.letterSpacing: 3
    }

    // sharp style
    Rectangle {
        id: block

        visible: !Theme.rounded
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 18
        color: Theme.accent
    }

    Text {
        id: label

        visible: !Theme.rounded
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

        visible: !Theme.rounded
        anchors.left: label.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "//"
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 12
    }

    Rectangle {
        visible: !Theme.rounded
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

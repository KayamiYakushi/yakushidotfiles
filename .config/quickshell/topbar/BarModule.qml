import QtQuick
import "../"

// One island module: optional icon, small label and a value.
// Hover grows it slightly (a transform, so the island never re-lays out)
// and tints interactive modules with the accent colour.
Item {
    id: m

    property string icon: ""
    property string label: ""
    property string value: ""
    property color valueColor: Theme.ink
    property bool bold: false
    property bool interactive: false
    property bool highlighted: false   // e.g. while its menu is open
    property int maxValueWidth: 0
    readonly property bool hovered: mouse.containsMouse

    signal clicked(int button)
    signal scrolled(int delta)

    implicitWidth: row.implicitWidth
    implicitHeight: 32
    height: parent ? parent.height : implicitHeight

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        scale: m.hovered ? 1.08 : 1.0
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic }
        }

        Text {
            visible: m.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: m.icon
            color: (m.interactive && m.hovered) || m.highlighted ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 13

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }
        }

        Text {
            visible: m.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: m.label
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1
        }

        Text {
            visible: m.value !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: m.maxValueWidth > 0 ? Math.min(implicitWidth, m.maxValueWidth) : implicitWidth
            text: m.value
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: m.interactive && m.hovered ? Theme.accent : m.valueColor
            font.family: Theme.mono
            font.pixelSize: 11
            font.bold: m.bold

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.leftMargin: -5
        anchors.rightMargin: -5
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: m.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: function(event) {
            m.clicked(event.button)
        }

        onWheel: function(event) {
            m.scrolled(event.angleDelta.y)
        }
    }
}

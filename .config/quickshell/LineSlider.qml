import QtQuick

// Compact slider without a header: a 4px track with a knob. `value` is owned
// by the caller; `sliding` fires while dragging, `settled` on release.
Item {
    id: root

    property real value: 0
    property color tint: Theme.accent
    property bool dimmed: false

    signal sliding(real value)
    signal settled(real value)

    implicitHeight: 18

    readonly property real shown: Math.max(0, Math.min(1, value))

    Rectangle {
        id: track

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: mouse.containsMouse || mouse.pressed ? 6 : 4
        radius: Theme.rounded ? (height / 2) : 0
        color: Theme.tint(Theme.ink, 0.10)

        Behavior on height {
            NumberAnimation { duration: Theme.tFast }
        }

        Rectangle {
            width: parent.width * root.shown
            height: parent.height
            radius: Theme.rounded ? (parent.radius) : 0
            color: root.dimmed ? Theme.inkSoft : root.tint
        }
    }

    Rectangle {
        x: track.width * root.shown - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: mouse.containsMouse || mouse.pressed ? 14 : 10
        height: width
        radius: Theme.rounded ? (width / 2) : 0
        color: Theme.ink

        Behavior on width {
            NumberAnimation { duration: Theme.tFast }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function valueAt(x) {
            return Math.max(0, Math.min(1, x / Math.max(1, width)))
        }

        onPressed: function(event) { root.sliding(valueAt(event.x)) }
        onPositionChanged: function(event) { if (pressed) root.sliding(valueAt(event.x)) }
        onReleased: function(event) { root.settled(valueAt(event.x)) }
    }
}

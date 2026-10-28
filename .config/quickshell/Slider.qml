import QtQuick

// Labelled 0..1 slider used across Settings.
//
//   value       the caller's value (the slider never overwrites it)
//   sliding(v)  while dragging
//   settled(v)  once, when the button is released
Item {
    id: slider

    property string label: ""
    property string icon: ""
    property real value: 0
    property color tint: Theme.accent

    signal sliding(real value)
    signal settled(real value)

    // While dragging the knob follows the pointer, otherwise the caller.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : value))

    implicitHeight: 50

    // ---- caption: glyph + label
    Text {
        id: glyph

        anchors.left: parent.left
        anchors.top: parent.top
        width: 22
        text: slider.icon
        color: slider.tint
        font.family: Theme.glyphs
        font.pixelSize: 15
    }

    Text {
        anchors.left: glyph.right
        anchors.right: parent.right
        anchors.verticalCenter: glyph.verticalCenter
        text: slider.label
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
        font.letterSpacing: 1
        elide: Text.ElideRight
    }

    // ---- bar
    Item {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: 16

        Rectangle {
            id: groove

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: Theme.rounded ? 2 : 0
            color: Theme.groove
            border.width: 1
            border.color: Theme.line
        }

        Rectangle {
            id: level

            anchors.left: groove.left
            anchors.verticalCenter: groove.verticalCenter
            width: groove.width * slider.shown
            height: groove.height
            radius: groove.radius
            color: slider.tint

            Behavior on width {
                enabled: !slider.dragging
                NumberAnimation { duration: Theme.tFast }
            }
        }

        // soft halo around the filled part
        Rectangle {
            x: level.x - 2
            y: level.y - 2
            width: level.width + 4
            height: level.height + 4
            radius: Theme.rounded ? 4 : 0
            color: "transparent"
            border.width: 2
            border.color: Theme.tint(slider.tint, 0.35)
        }

        Rectangle {
            id: knob

            x: level.width - width / 2
            anchors.verticalCenter: groove.verticalCenter
            width: 12
            height: 12
            radius: Theme.rounded ? 6 : 0
            color: Theme.ink
            border.width: 2
            border.color: slider.tint
            scale: slider.dragging ? 1.4 : 1

            Behavior on scale {
                NumberAnimation { duration: Theme.tFast }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            preventStealing: true

            function follow(px) {
                slider.dragValue = Math.max(0, Math.min(1, px / Math.max(1, groove.width)))
                slider.sliding(slider.dragValue)
            }

            onPressed: function(mouse) {
                slider.dragging = true
                follow(mouse.x)
            }

            onPositionChanged: function(mouse) {
                if (pressed)
                    follow(mouse.x)
            }

            onReleased: {
                slider.settled(slider.dragValue)
                slider.dragging = false
            }

            onCanceled: slider.dragging = false
        }
    }
}

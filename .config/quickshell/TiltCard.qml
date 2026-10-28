import QtQuick

// The Settings card: it swings in from an angle when shown (with a small
// overshoot as it lands) and, while the pointer is over it, leans a few
// degrees toward the pointer.
//
//   shown        visible or not
//   leanDegrees  how far it leans toward the pointer
Item {
    id: card

    default property alias content: inside.data
    property bool shown: false
    property real leanDegrees: 5

    // pointer position over the card, centre = (0, 0), edges = ±0.5
    property point pointer: Qt.point(0, 0)

    // the three animated values the transform reads
    property real tiltX: shown ? -pointer.y * leanDegrees : 20
    property real tiltY: shown ? pointer.x * leanDegrees : -16
    property real size: shown ? 1 : 0.88

    Behavior on tiltX { NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic } }
    Behavior on tiltY { NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic } }
    Behavior on size { NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutBack } }

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }

    readonly property real cx: width / 2
    readonly property real cy: height / 2

    transform: [
        Rotation { origin { x: card.cx; y: card.cy } axis { x: 1; y: 0; z: 0 } angle: card.tiltX },
        Rotation { origin { x: card.cx; y: card.cy } axis { x: 0; y: 1; z: 0 } angle: card.tiltY },
        Scale { origin { x: card.cx; y: card.cy } xScale: card.size; yScale: card.size }
    ]

    HoverHandler {
        onPointChanged: card.pointer = Qt.point(point.position.x / Math.max(1, card.width) - 0.5,
                                                point.position.y / Math.max(1, card.height) - 0.5)
        onHoveredChanged: if (!hovered) card.pointer = Qt.point(0, 0)
    }

    Item {
        id: inside
        anchors.fill: parent
    }
}

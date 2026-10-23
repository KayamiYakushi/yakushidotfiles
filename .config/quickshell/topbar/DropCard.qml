import QtQuick
import QtQuick.Shapes
import "../"

// A card that hangs from the island's lower edge below a module, joined to
// the island by concave "ears", and grows downward when opened.
// Used for the now-playing card and the power menu. Nothing is drawn while
// closed.
Item {
    id: drop

    required property Item island
    required property real islandEar
    required property real islandCorner
    required property real fillOpacity

    property bool open: false
    property real anchorX: 0          // centre of the module it belongs to
    property real cardWidth: 360      // without the ears
    property real cardHeight: 140
    property real minWidth: 300
    property real ear: 12

    default property alias content: inner.data
    readonly property bool hovered: hover.hovered
    readonly property real innerWidth: inner.width

    // Fits under the flat part of a narrow island.
    readonly property real fullWidth: Math.max(minWidth, Math.min(
        cardWidth + 2 * ear,
        island.width - 2 * islandEar - 2 * islandCorner))

    // Keep the top edge under the flat part of the island, so the two shapes
    // always join cleanly.
    readonly property real minX: island.x + islandEar + islandCorner
    readonly property real maxX: island.x + island.width - islandEar - islandCorner - fullWidth

    property real openness: open ? 1 : 0

    x: maxX >= minX
        ? Math.max(minX, Math.min(maxX, anchorX - fullWidth / 2))
        : island.x + (island.width - fullWidth) / 2
    y: island.y + island.height
    width: fullWidth
    height: cardHeight * openness
    visible: openness > 0.001
    clip: true

    Behavior on openness {
        NumberAnimation { duration: Theme.animMed + 60; easing.type: Easing.OutCubic }
    }

    HoverHandler {
        id: hover
    }

    Shape {
        id: shape

        readonly property real h: drop.height
        readonly property real e: Math.max(0.01, Math.min(drop.ear, h))
        readonly property real r: Math.max(0.01, Math.min(22, (h - e) / 2))

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Qt.rgba(0.02, 0.02, 0.02, drop.fillOpacity)
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0

            PathLine { x: drop.width; y: 0 }
            PathArc {
                x: drop.width - drop.ear; y: shape.e
                radiusX: drop.ear; radiusY: shape.e
                direction: PathArc.Counterclockwise
            }
            PathLine { x: drop.width - drop.ear; y: shape.h - shape.r }
            PathArc {
                x: drop.width - drop.ear - shape.r; y: shape.h
                radiusX: shape.r; radiusY: shape.r
                direction: PathArc.Clockwise
            }
            PathLine { x: drop.ear + shape.r; y: shape.h }
            PathArc {
                x: drop.ear; y: shape.h - shape.r
                radiusX: shape.r; radiusY: shape.r
                direction: PathArc.Clockwise
            }
            PathLine { x: drop.ear; y: shape.e }
            PathArc {
                x: 0; y: 0
                radiusX: drop.ear; radiusY: shape.e
                direction: PathArc.Counterclockwise
            }
        }
    }

    Item {
        id: inner

        x: drop.ear
        width: drop.fullWidth - 2 * drop.ear
        height: drop.cardHeight
        opacity: drop.open ? 1 : 0

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: drop.open ? 90 : 0 }
                NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic }
            }
        }
    }
}

import QtQuick

// Thin scroll position indicator for a Flickable, drawn in the page's right
// margin. Shown only when the content is taller than the view.
Rectangle {
    required property Flickable flick

    visible: flick.contentHeight > flick.height + 1
    x: flick.x + flick.width + 13
    y: flick.y + (flick.height - height) * Math.max(0, Math.min(1,
        flick.contentY / Math.max(1, flick.contentHeight - flick.height)))
    width: 2
    height: Math.max(24, flick.height * flick.height / Math.max(1, flick.contentHeight))
    radius: 1
    color: Theme.alpha(Theme.text, flick.moving ? 0.45 : 0.18)

    Behavior on color {
        ColorAnimation { duration: Theme.animFast }
    }
}

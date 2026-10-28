import QtQuick
import QtQuick.Shapes

// A few faint sakura petals that have drifted onto the inside of the Settings
// frame. The arrangement is random every time Settings opens: petals fall in
// small clusters of varying size, rotation and softness, so nothing looks
// placed by hand. Every petal keeps clear of the frame edge by construction.
//
// Static: no timers and no animation, so it costs nothing while Settings is
// open. When `active` is false no petal items exist at all.
Item {
    id: root

    property bool active: false
    property color tint: "#ff7a9d"
    property var petals: []

    // Stretch near the corners that stays clear (HUD corner brackets).
    readonly property real cornerGap: 62

    function pick(min, max) {
        return min + Math.random() * (max - min)
    }

    function generate() {
        var list = []
        var clusters = 4 + Math.floor(Math.random() * 3)

        for (var c = 0; c < clusters; ++c) {
            var edge = Math.floor(Math.random() * 4)
            var centre = pick(0.04, 0.96)
            var count = 1 + Math.floor(Math.random() * 4)

            for (var i = 0; i < count; ++i) {
                var s = pick(0.40, 0.92)

                list.push({
                    e: edge,
                    p: Math.max(0.02, Math.min(0.98, centre + pick(-0.07, 0.07))),
                    // half the petal's rotated diagonal, plus a little room
                    d: 18 * s + 2 + Math.random() * Math.random() * 40,
                    s: s,
                    r: Math.random() * 360,
                    a: pick(0.20, 0.40),
                    l: Math.random() < 0.4 ? 1 : 0
                })
            }
        }

        return list
    }

    function refresh() {
        petals = active ? generate() : []
    }

    onActiveChanged: refresh()
    Component.onCompleted: refresh()

    function shade(light, alpha) {
        var c = light ? Qt.lighter(root.tint, 1.2) : root.tint
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    function centreX(e, p, d) {
        if (e === 1) return root.width - d
        if (e === 3) return d
        return root.cornerGap + p * Math.max(0, root.width - 2 * root.cornerGap)
    }

    function centreY(e, p, d) {
        if (e === 0) return d
        if (e === 2) return root.height - d
        return root.cornerGap + p * Math.max(0, root.height - 2 * root.cornerGap)
    }

    Repeater {
        model: root.active ? root.petals : []

        delegate: Shape {
            id: petal

            required property var modelData

            width: 22
            height: 28
            x: root.centreX(modelData.e, modelData.p, modelData.d) - width / 2
            y: root.centreY(modelData.e, modelData.p, modelData.d) - height / 2
            scale: modelData.s
            rotation: modelData.r
            antialiasing: true
            enabled: false

            ShapePath {
                strokeColor: "transparent"

                fillGradient: LinearGradient {
                    x1: 11; y1: 28
                    x2: 11; y2: 0

                    GradientStop {
                        position: 0.0
                        color: root.shade(petal.modelData.l, petal.modelData.a)
                    }

                    GradientStop {
                        position: 1.0
                        color: root.shade(1, petal.modelData.a * 0.4)
                    }
                }

                PathSvg {
                    path: "M11 28 C3 22 0 12 4 4 C6 1 9 2 11 6 C13 2 16 1 18 4 C22 12 19 22 11 28 Z"
                }
            }
        }
    }
}

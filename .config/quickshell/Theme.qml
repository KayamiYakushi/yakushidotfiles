pragma Singleton
import QtQuick

// Yakushi design tokens: every Settings / bar colour, font and timing comes
// from here, so a change in one place restyles everything.
QtObject {
    // ---- surfaces
    property real glass: 0.8                       // Settings panel opacity (Appearance)
    property color backdrop: Qt.rgba(0, 0, 0, glass)
    readonly property color surface: "#060606"
    readonly property color card: "#0e0e0e"
    readonly property color groove: "#171717"
    readonly property color line: "#1f1f1f"
    readonly property color lineHot: "#2b2b2b"

    // ---- ink
    readonly property color ink: "#ffffff"
    readonly property color inkSoft: "#a6a6a6"
    readonly property color inkMute: "#707070"

    // ---- signal colours
    property color accent: "#ffffff"              // Appearance -> Accent
    property color accentAlt: accent
    readonly property color alert: "#ff2e4d"
    readonly property color good: "#2ee6a0"

    // ---- type
    readonly property string mono: "JetBrainsMono Nerd Font"
    property string glyphs: "JetBrainsMono Nerd Font"

    // ---- shape: sharp (false) or rounded (true), Appearance -> Style
    property bool rounded: false
    readonly property int corner: rounded ? 6 : 0
    readonly property int cornerLarge: rounded ? 12 : 0

    // ---- motion (ms)
    readonly property int tFast: 120
    readonly property int tMid: 220
    readonly property int tSlow: 380

    // `c` with alpha `a`
    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
}

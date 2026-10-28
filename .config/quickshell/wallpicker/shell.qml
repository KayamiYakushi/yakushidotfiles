import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Yakushi wallpaper picker (SUPER + W).
//
// A strip of sharp-edged thumbnails across the middle of the screen. They
// grow toward the centre like a dock, and the one in the middle opens up to
// its real 16:9 shape at full brightness. One wheel notch or arrow key moves
// one wallpaper; click, Space or Enter applies; Esc or W closes.
//
// Layout: `pos` is the (fractional) index at the centre of the screen. Every
// tile's size and place is a function of its distance from `pos`, stacked
// edge to edge, so nothing overlaps or jitters while the strip moves.
PanelWindow {
    id: picker

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string here: Quickshell.shellDir

    // ---- look
    readonly property real middleScale: 0.8      // size of the centre tile
    readonly property real edgeScale: 0.3        // size at the screen edges
    readonly property real wideAspect: 16 / 9    // shape of the centre tile
    readonly property int gap: 10
    readonly property int stripHeight: 500
    readonly property int firstIndex: 20         // where the strip starts
    readonly property real speed: 5000           // px / s while moving

    implicitWidth: Screen.width
    implicitHeight: stripHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function expand(path) {
        return String(path || "").replace(/^~(?=\/|$)/, home)
    }

    // settings.json next to this file
    FileView {
        path: picker.here + "/settings.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: cfg

            property string images_dir
            property string thumbs_dir
            property int visible_count: 10
            property string frame_color: "#80FFFFFF"
        }
    }

    // Thumbnails are made in the background; missing ones retry below.
    Component.onCompleted: Quickshell.execDetached(["sh", here + "/thumbs.sh", here])

    FolderListModel {
        id: files

        folder: "file://" + picker.expand(cfg.images_dir)
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]

        onCountChanged: {
            if (!strip.started && count > 0) {
                strip.jump(Math.min(picker.firstIndex, count - 1))
                strip.started = true
            }
        }
    }

    // ------------------------------------------------------------------
    // Strip
    // ------------------------------------------------------------------
    Item {
        id: strip

        anchors.fill: parent
        focus: true

        property bool started: false
        property int target: 0          // index the strip moves to / rests on
        property int marked: 0          // framed tile (hovered or target)
        property real pos: 0            // index at the centre, animated

        Behavior on pos {
            enabled: strip.started

            SmoothedAnimation {
                velocity: picker.speed / strip.slot
                duration: 1000
            }
        }

        // ---- geometry
        readonly property real slot: width / Math.max(1, cfg.visible_count) - 10
        readonly property real half: width / 2
        readonly property real reach: Math.max(1, half / (slot + picker.gap))
        readonly property real wide: Math.min(picker.stripHeight * picker.middleScale * picker.wideAspect, width * 0.5)

        function smooth(x) {
            return x * x * (3 - 2 * x)
        }

        // dock size by distance d (in tiles) from the centre
        function sizeAt(d) {
            var t = 1 - smooth(Math.min(1, Math.abs(d) / reach))
            return picker.edgeScale + (picker.middleScale - picker.edgeScale) * t
        }

        // 1 at the centre, 0 from one tile away
        function opennessAt(d) {
            return smooth(Math.max(0, 1 - Math.abs(d)))
        }

        function widthAt(d) {
            var normal = slot * sizeAt(d)
            return normal + (wide - normal) * opennessAt(d)
        }

        // centre-to-centre distance between tile d and tile d + 1
        function pitch(d) {
            return (widthAt(d) + widthAt(d + 1)) / 2 + picker.gap
        }

        // horizontal offset of tile d from the screen centre
        function offset(d) {
            var a = Math.floor(pos) - pos                // tile left of centre, -1 < a <= 0
            var steps = Math.round(d - a)
            var x = a * pitch(a)
            for (var i = 0; i < steps; i++)
                x += pitch(a + i)
            for (var j = -1; j >= steps; j--)
                x -= pitch(a + j)
            return x
        }

        // ---- moving
        function jump(i) {
            target = i
            marked = i
            pos = i
        }

        function go(i) {
            target = Math.max(0, Math.min(files.count - 1, i))
            marked = target
            pos = target
        }

        function apply(i) {
            var file = files.get(i, "filePath")
            if (file)
                Quickshell.execDetached(["sh", picker.here + "/apply.sh", file])
            Qt.quit()
        }

        // wheel: one notch (120) = one wallpaper; smooth wheels and touchpads
        // add up first, a pause or a change of direction starts over
        property real wheelSum: 0

        function wheel(event) {
            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
            if (!wheelPause.running || delta * wheelSum < 0)
                wheelSum = 0
            wheelPause.restart()
            wheelSum += delta
            while (Math.abs(wheelSum) >= 120) {
                var dir = wheelSum > 0 ? 1 : -1
                wheelSum -= 120 * dir
                go(target + dir)
            }
            event.accepted = true
        }

        Timer {
            id: wheelPause
            interval: 400
        }

        WheelHandler {
            onWheel: function(event) { strip.wheel(event) }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left)
                strip.go(strip.target - 1)
            else if (event.key === Qt.Key_Right)
                strip.go(strip.target + 1)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                strip.apply(strip.marked)
            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_W)
                Qt.quit()
            else
                return
            event.accepted = true
        }

        // ---- tiles (only the ones on screen load their picture)
        Repeater {
            model: files

            delegate: Item {
                id: tile

                required property int index
                required property string fileName

                readonly property real d: index - strip.pos
                readonly property real open: strip.opennessAt(d)
                readonly property real middle: strip.half + strip.offset(d)
                readonly property bool onScreen: middle + width / 2 > 0 && middle - width / 2 < strip.width
                property bool seen: false

                onOnScreenChanged: if (onScreen) seen = true
                Component.onCompleted: if (onScreen) seen = true

                width: strip.widthAt(d)
                height: picker.stripHeight * Math.min(1, strip.sizeAt(d))
                x: middle - width / 2
                y: (picker.stripHeight - height) / 2
                visible: onScreen

                Text {
                    id: waiting

                    anchors.centerIn: parent
                    color: cfg.frame_color
                    font.pixelSize: 16
                }

                Image {
                    id: picture

                    anchors.fill: parent
                    opacity: 0.8 + 0.2 * tile.open
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    sourceSize.width: strip.wide
                    sourceSize.height: picker.stripHeight
                    source: tile.seen ? "file://" + picker.expand(cfg.thumbs_dir) + tile.fileName : ""

                    // the thumbnail may still be being made: try again
                    onStatusChanged: {
                        if (status === Image.Error) {
                            waiting.text = "Caching"
                            again.restart()
                        }
                    }

                    Timer {
                        id: again

                        interval: 1000
                        onTriggered: {
                            var src = picture.source
                            picture.source = ""
                            picture.source = src
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: strip.marked === tile.index
                    color: "transparent"
                    border.width: 2
                    border.color: cfg.frame_color
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: strip.marked = tile.index
                    onClicked: strip.apply(tile.index)
                    onWheel: function(event) { strip.wheel(event) }
                }
            }
        }
    }
}

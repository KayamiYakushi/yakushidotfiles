import Quickshell
import Quickshell.Io
import QtQuick
import "../"

// Top bar settings, read from ~/.config/quickshell/yakushi-topbar.local.json
// (written by Settings -> Top Bar). The file is watched with inotify and
// Settings also pings the bar over IPC, so changes apply instantly with no
// polling. The accent colour follows Settings -> Appearance the same way.
Item {
    id: cfg

    visible: false

    readonly property string home: Quickshell.env("HOME") || ""

    property string style: "island"
    property bool seconds: true
    property bool clock24: true
    property real barOpacity: 0.90
    property string visualizer: "hover"

    readonly property var defaultOrder: [
        "workspaces", "ram", "cpu", "cpuTemp", "gpuTemp",
        "date", "time", "media", "volume", "power"
    ]
    property var order: defaultOrder
    property var modules: ({
        workspaces: true,
        ram: true,
        cpu: true,
        cpuTemp: true,
        gpuTemp: true,
        media: true,
        volume: true,
        date: true,
        time: true,
        power: true
    })

    function reload() {
        stateFile.reload()
        uiFile.reload()
    }

    function apply(raw) {
        var data

        try {
            data = JSON.parse(raw)
        } catch (e) {
            // Caught the file mid-write: read it again shortly.
            retry.restart()
            return
        }

        if (!data || typeof data !== "object")
            return

        if (data.style === "island" || data.style === "waybar")
            style = data.style

        if (typeof data.seconds === "boolean")
            seconds = data.seconds

        if (typeof data.clock24 === "boolean")
            clock24 = data.clock24

        if (typeof data.opacity === "number")
            barOpacity = Math.max(0.40, Math.min(1.0, data.opacity))

        if (data.visualizer === "hover" || data.visualizer === "always" || data.visualizer === "off")
            visualizer = data.visualizer

        if (Array.isArray(data.order)) {
            var seen = {}
            var list = []

            data.order.concat(defaultOrder).forEach(function(key) {
                if (defaultOrder.indexOf(key) >= 0 && !seen[key]) {
                    seen[key] = true
                    list.push(key)
                }
            })

            if (list.join() !== order.join())
                order = list
        }

        if (data.modules && typeof data.modules === "object") {
            var next = {}

            for (var key in modules)
                next[key] = typeof data.modules[key] === "boolean"
                    ? data.modules[key]
                    : modules[key]

            modules = next
        }
    }

    function applyUi(raw) {
        try {
            var data = JSON.parse(raw)

            if (typeof data.accent === "string" && /^#[0-9a-fA-F]{6}$/.test(data.accent))
                Theme.accent = data.accent
        } catch (e) {
        }
    }

    Timer {
        id: retry
        interval: 150
        repeat: false
        onTriggered: stateFile.reload()
    }

    FileView {
        id: stateFile

        path: cfg.home + "/.config/quickshell/yakushi-topbar.local.json"
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: cfg.apply(text())
    }

    FileView {
        id: uiFile

        path: cfg.home + "/.config/quickshell/yakushi-ui.local.json"
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: cfg.applyUi(text())
    }
}

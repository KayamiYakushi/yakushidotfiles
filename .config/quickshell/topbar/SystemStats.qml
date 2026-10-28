import Quickshell
import Quickshell.Io
import QtQuick

// RAM, CPU usage and temperatures for the top bar.
//
// Cost: one 2-second timer that re-reads a few small kernel files
// (/proc/stat, /proc/meminfo, two hwmon inputs). No processes are spawned
// after start-up, and anything whose module is switched off is not read.
Item {
    id: stats

    visible: false

    required property var config

    readonly property bool wantCpu: config.modules.cpu
    readonly property bool wantRam: config.modules.ram
    readonly property bool wantCpuTemp: config.modules.cpuTemp && cpuTempPath !== ""
    readonly property bool wantGpuTemp: config.modules.gpuTemp && gpuTempPath !== ""

    property real cpuPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property int cpuTemp: -1
    property int gpuTemp: -1

    property string cpuTempPath: ""
    property string gpuTempPath: ""

    property real lastBusy: -1
    property real lastTotal: -1

    function readTemp(raw) {
        var milli = parseInt(raw)
        return isNaN(milli) ? -1 : Math.round(milli / 1000)
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: stats.wantCpu || stats.wantRam || stats.wantCpuTemp || stats.wantGpuTemp

        onTriggered: {
            if (stats.wantCpu)
                procStat.reload()
            if (stats.wantRam)
                memInfo.reload()
            if (stats.wantCpuTemp)
                cpuTempFile.reload()
            if (stats.wantGpuTemp)
                gpuTempFile.reload()
        }
    }

    FileView {
        id: procStat

        path: "/proc/stat"
        printErrors: false

        onLoaded: {
            // first line: "cpu  user nice system idle iowait irq softirq steal ..."
            var t = text().slice(0, text().indexOf("\n")).trim().split(/\s+/).slice(1, 9).map(Number)
            if (t.length < 8 || t.some(isNaN))
                return

            var total = 0
            t.forEach(function(n) { total += n })
            var busy = total - t[3] - t[4]

            if (stats.lastTotal >= 0 && total > stats.lastTotal)
                stats.cpuPercent = Math.max(0, Math.min(100,
                    100 * (busy - stats.lastBusy) / (total - stats.lastTotal)))

            stats.lastBusy = busy
            stats.lastTotal = total
        }
    }

    FileView {
        id: memInfo

        path: "/proc/meminfo"
        printErrors: false

        onLoaded: {
            var t = text()
            var total = t.match(/MemTotal:\s+(\d+)/)
            var avail = t.match(/MemAvailable:\s+(\d+)/)

            if (!total || !avail)
                return

            // kB -> GiB, matching what Waybar showed.
            stats.ramTotalGb = Number(total[1]) / 1048576
            stats.ramUsedGb = (Number(total[1]) - Number(avail[1])) / 1048576
        }
    }

    FileView {
        id: cpuTempFile

        path: stats.cpuTempPath
        printErrors: false
        onLoaded: stats.cpuTemp = stats.readTemp(text())
    }

    FileView {
        id: gpuTempFile

        path: stats.gpuTempPath
        printErrors: false
        onLoaded: stats.gpuTemp = stats.readTemp(text())
    }

    // Find the temperature sensors once (hwmon numbers change between boots).
    Process {
        running: true
        command: [
            "python3",
            (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/yakushi-topbarctl.py",
            "sensors"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.cpu)
                        stats.cpuTempPath = data.cpu
                    if (data.gpu)
                        stats.gpuTempPath = data.gpu
                } catch (e) {
                }
            }
        }
    }
}

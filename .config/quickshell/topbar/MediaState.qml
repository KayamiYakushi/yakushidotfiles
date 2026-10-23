import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Shared now-playing state plus the audio spectrum (cava) for the
// visualizer. One instance serves every screen.
//
// cava is started only while a visualizer is actually on screen and music
// is playing; otherwise no process runs at all.
Item {
    id: media

    visible: false

    required property var config

    // -------------------------
    // Player: the one playing, else the first
    // -------------------------
    readonly property var player: {
        var list = Mpris.players.values
        for (var i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Playing)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    readonly property bool playing: player !== null
        && player.playbackState === MprisPlaybackState.Playing

    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string artUrl: player ? (player.trackArtUrl || "") : ""

    readonly property string trackText: title === ""
        ? ""
        : (artist !== "" ? title + " — " + artist : title)

    // -------------------------
    // Spectrum
    // -------------------------
    readonly property int barCount: 6

    // Visualizers currently on screen and asking for data.
    property int demand: 0

    readonly property bool spectrumWanted: config.visualizer !== "off"
        && playing
        && (config.visualizer === "always" || demand > 0)

    property var levels: [0, 0, 0, 0, 0, 0]

    function request(on) {
        demand = Math.max(0, demand + (on ? 1 : -1))
    }

    onSpectrumWantedChanged: {
        if (!spectrumWanted)
            levels = [0, 0, 0, 0, 0, 0]
    }

    Process {
        id: cava

        running: media.spectrumWanted
        command: [
            "cava", "-p",
            (Quickshell.env("HOME") || "") + "/.config/quickshell/topbar/cava.conf"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.split(";")
                var next = []

                for (var i = 0; i < media.barCount; i++) {
                    var v = parseInt(parts[i])
                    next.push(isNaN(v) ? 0 : Math.min(1, v / 100))
                }

                media.levels = next
            }
        }
    }
}

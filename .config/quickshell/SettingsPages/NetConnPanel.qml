import QtQuick
import Quickshell.Io
import "../"

// The settings of one connection (Ethernet or Wi-Fi), opened under its row
// in Settings -> Network: what it uses right now, DNS, the IP address and
// auto-connect. SAVE sends only what you changed (yakushi-netctl.py apply).
Rectangle {
    id: panel

    required property string uuid
    required property string helper
    property bool canForget: false
    property string link: ""             // Wi-Fi rate, from the network list

    signal saved(string message)         // saved or forgotten: refresh the list

    // what NetworkManager has
    property var info: null
    property string message: ""
    property bool working: job.running

    // what you are editing
    property string dnsPick: "auto"      // auto | cloudflare | google | quad9 | adguard | custom
    property string dnsText: ""
    property string ipPick: "auto"       // auto | manual
    property string addrText: ""
    property string gwText: ""
    property bool autoOn: true

    readonly property var presets: [
        { id: "cloudflare", name: "CLOUDFLARE", servers: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"] },
        { id: "google", name: "GOOGLE", servers: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"] },
        { id: "quad9", name: "QUAD9", servers: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"] },
        { id: "adguard", name: "ADGUARD", servers: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"] }
    ]

    function presetOf(id) {
        for (var i = 0; i < presets.length; i++)
            if (presets[i].id === id)
                return presets[i]
        return null
    }

    // which chip a saved DNS list matches (IPv4 servers decide)
    function pickFor(dns) {
        if (!dns || dns.length === 0)
            return "auto"
        var v4 = dns.filter(function(s) { return s.indexOf(":") < 0 }).join(",")
        for (var i = 0; i < presets.length; i++)
            if (presets[i].servers.filter(function(s) { return s.indexOf(":") < 0 }).join(",") === v4)
                return presets[i].id
        return "custom"
    }

    function load(d) {
        info = d
        if (!d)
            return
        dnsPick = pickFor(d.dns)
        dnsText = (d.dns || []).join(", ")
        ipPick = d.ipMode === "manual" ? "manual" : "auto"
        addrText = d.address || (d.now && d.now.ip && d.now.ip.length ? d.now.ip[0] : "")
        gwText = d.gateway || (d.now ? d.now.gateway || "" : "")
        autoOn = d.autoconnect !== false
    }

    function dnsList() {
        if (dnsPick === "custom")
            return dnsText.split(/[\s,;]+/).filter(function(s) { return s !== "" })
        var p = presetOf(dnsPick)
        return p ? p.servers : []
    }

    readonly property bool dnsDirty: info !== null && (dnsPick !== pickFor(info.dns)
        || (dnsPick === "custom" && dnsList().join(",") !== (info.dns || []).join(",")))
    readonly property bool ipDirty: info !== null && (ipPick !== info.ipMode
        || (ipPick === "manual" && (addrText !== (info.address || "") || gwText !== (info.gateway || ""))))
    readonly property bool autoDirty: info !== null && autoOn !== (info.autoconnect !== false)
    readonly property bool dirty: dnsDirty || ipDirty || autoDirty

    function save() {
        if (!dirty || working)
            return
        var w = {}
        if (autoDirty)
            w.autoconnect = autoOn
        if (ipDirty || (dnsDirty && ipPick === "manual")) {
            w.ipMode = ipPick
            if (ipPick === "manual") {
                w.address = addrText.trim()
                w.gateway = gwText.trim()
            }
        }
        if (dnsDirty || (ipDirty && ipPick === "manual")) {
            w.dnsMode = dnsPick === "auto" ? "auto" : "custom"
            if (dnsPick !== "auto")
                w.dns = dnsList()
        }
        message = "Saving..."
        run(["apply", uuid, JSON.stringify(w)])
    }

    function forget() {
        if (working)
            return
        message = "Forgetting..."
        run(["forget", uuid])
    }

    function run(args) {
        job.command = ["python3", helper].concat(args)
        job.running = true
    }

    Process {
        id: job

        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try {
                    d = JSON.parse(text)
                } catch (e) {
                    panel.message = "NetworkManager did not answer."
                    return
                }
                var cmd = job.command[2]
                if (cmd === "forget") {
                    panel.saved(d.message || "Forgotten.")
                    return
                }
                if (d.details)
                    panel.load(d.details)
                panel.message = d.message || ""
                if (cmd === "apply" && d.ok)
                    panel.saved(d.message || "Saved.")
            }
        }
    }

    Component.onCompleted: run(["details", uuid])

    implicitHeight: body.implicitHeight + 28
    color: Theme.card
    border.width: 1
    border.color: Theme.line

    // ---- small parts
    component Caption: Text {
        textFormat: Text.PlainText
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        font.letterSpacing: 2
    }

    component Fact: Column {
        property string key: ""
        property string value: ""

        spacing: 3

        Text {
            textFormat: Text.PlainText
            text: parent.key
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 8
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: parent.value !== "" ? parent.value : "—"
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
        }
    }

    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false

        signal picked()

        width: chipText.implicitWidth + 20
        height: 24
        color: on ? Theme.tint(Theme.accent, 0.16)
            : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.06) : "transparent"
        border.width: 1
        border.color: on ? Theme.accent : chipMouse.containsMouse ? Theme.lineHot : Theme.line

        Text {
            id: chipText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component Field: Rectangle {
        id: field

        property alias text: input.text
        property string hint: ""

        signal accepted()

        height: 30
        color: Theme.tint(Theme.ink, 0.03)
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : Theme.line

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            color: Theme.ink
            selectionColor: Theme.tint(Theme.accent, 0.4)
            font.family: Theme.mono
            font.pixelSize: 11

            Keys.onReturnPressed: field.accepted()
            Keys.onEnterPressed: field.accepted()

            Text {
                textFormat: Text.PlainText
                visible: input.text === "" && !input.activeFocus
                anchors.verticalCenter: parent.verticalCenter
                text: field.hint
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }

    component PanelButton: Rectangle {
        id: act

        property string label: ""
        property bool danger: false
        property bool on: true

        signal clicked()

        width: actText.implicitWidth + 26
        height: 28
        opacity: on ? 1 : 0.4
        color: danger ? (actMouse.containsMouse && on ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, actMouse.containsMouse && on ? 0.28 : 0.14)
        border.width: 1
        border.color: danger ? Theme.tint(Theme.alert, 0.6) : Theme.tint(Theme.accent, 0.8)

        Text {
            id: actText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: act.label
            color: act.danger ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        MouseArea {
            id: actMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: act.on
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
    }

    Column {
        id: body

        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12

        Text {
            textFormat: Text.PlainText
            visible: panel.info === null
            text: panel.message !== "" ? panel.message : "Reading the settings..."
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
        }

        // ---- what it uses right now
        Grid {
            id: facts

            visible: panel.info !== null && panel.info.active
            width: parent.width
            columns: width > 540 ? 3 : 2
            columnSpacing: 16
            rowSpacing: 10

            readonly property real cell: (width - columnSpacing * (columns - 1)) / columns
            readonly property var now: panel.info && panel.info.now ? panel.info.now : ({})

            Fact { width: facts.cell; key: "IP ADDRESS"; value: (facts.now.ip || []).join(", ") }
            Fact { width: facts.cell; key: "GATEWAY"; value: facts.now.gateway || "" }
            Fact { width: facts.cell; key: "DNS IN USE"; value: (facts.now.dns || []).join(", ") }
            Fact { width: facts.cell; key: "IPV6"; value: (facts.now.ip6 || []).join(", ") }
            Fact { width: facts.cell; key: "MAC"; value: facts.now.mac || "" }
            Fact { width: facts.cell; key: "LINK"; value: facts.now.speed || panel.link }
        }

        Text {
            textFormat: Text.PlainText
            visible: panel.info !== null && !panel.info.active
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Not connected now. What you save here is used the next time it connects."
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 9
        }

        Rectangle {
            visible: panel.info !== null
            width: parent.width
            height: 1
            color: Theme.line
        }

        // ---- DNS
        Column {
            visible: panel.info !== null
            width: parent.width
            spacing: 8

            Caption { text: "DNS" }

            Flow {
                width: parent.width
                spacing: 6

                Chip {
                    label: "AUTOMATIC"
                    on: panel.dnsPick === "auto"
                    onPicked: panel.dnsPick = "auto"
                }

                Repeater {
                    model: panel.presets

                    delegate: Chip {
                        required property var modelData

                        label: modelData.name
                        on: panel.dnsPick === modelData.id
                        onPicked: panel.dnsPick = modelData.id
                    }
                }

                Chip {
                    label: "CUSTOM"
                    on: panel.dnsPick === "custom"
                    onPicked: {
                        if (panel.dnsPick !== "custom" && panel.dnsPick !== "auto")
                            panel.dnsText = panel.dnsList().join(", ")
                        panel.dnsPick = "custom"
                    }
                }
            }

            Field {
                visible: panel.dnsPick === "custom"
                width: parent.width
                hint: "DNS servers, e.g. 1.1.1.1, 9.9.9.9"
                text: panel.dnsText
                onTextChanged: panel.dnsText = text
                onAccepted: panel.save()
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: panel.dnsPick === "auto" ? "From your router (DHCP)."
                    : panel.dnsPick === "custom" ? "IPv4 and IPv6 servers, separated by commas."
                    : panel.dnsList().filter(function(s) { return s.indexOf(":") < 0 }).join("  ·  ") + "  (+ IPv6)"
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
            }
        }

        // ---- IP address
        Column {
            visible: panel.info !== null
            width: parent.width
            spacing: 8

            Caption { text: "IP ADDRESS" }

            Row {
                spacing: 6

                Chip {
                    label: "AUTOMATIC (DHCP)"
                    on: panel.ipPick === "auto"
                    onPicked: panel.ipPick = "auto"
                }

                Chip {
                    label: "MANUAL"
                    on: panel.ipPick === "manual"
                    onPicked: {
                        panel.ipPick = "manual"
                        if (panel.dnsPick === "auto")      // a fixed address gets no DNS by itself
                            panel.dnsPick = "cloudflare"
                    }
                }
            }

            Row {
                visible: panel.ipPick === "manual"
                width: parent.width
                spacing: 8

                Field {
                    width: (parent.width - 8) * 0.55
                    hint: "Address, e.g. 192.168.1.50/24"
                    text: panel.addrText
                    onTextChanged: panel.addrText = text
                    onAccepted: panel.save()
                }

                Field {
                    width: (parent.width - 8) * 0.45
                    hint: "Gateway, e.g. 192.168.1.1"
                    text: panel.gwText
                    onTextChanged: panel.gwText = text
                    onAccepted: panel.save()
                }
            }
        }

        // ---- auto-connect
        Item {
            visible: panel.info !== null
            width: parent.width
            height: 22

            Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: "CONNECT AUTOMATICALLY"
            }

            Switch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.autoOn
                onToggled: panel.autoOn = !panel.autoOn
            }
        }

        // ---- save / forget
        Item {
            visible: panel.info !== null
            width: parent.width
            height: 28

            PanelButton {
                id: forgetButton

                visible: panel.canForget
                anchors.left: parent.left
                label: "FORGET NETWORK"
                danger: true
                on: !panel.working
                onClicked: panel.forget()
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: forgetButton.visible ? forgetButton.right : parent.left
                anchors.leftMargin: forgetButton.visible ? 12 : 0
                anchors.right: saveButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: panel.message !== "" ? panel.message : panel.dirty ? "Not saved yet." : ""
                color: panel.message !== "" ? Theme.accent : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
            }

            PanelButton {
                id: saveButton

                anchors.right: parent.right
                label: panel.working ? "SAVING…" : "SAVE"
                on: panel.dirty && !panel.working
                onClicked: panel.save()
            }
        }
    }
}

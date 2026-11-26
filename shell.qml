// drift: snow on the desktop. It falls in three depths (the farthest behind the windows), sways and blows
// in gusts, settles on the top of the focused window and along the bottom of the screen, slides off a window that moves or closes, and parts around
// the cursor, which also sweeps settled snow off an edge. Clicks go straight through it.
import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ~/.config/drift/settings.json, read again whenever it changes
    readonly property var defaults: ({ amount: 1.0, wind: 1.0, settle: true, cursor: true, behind: true, melt: 0.3, color: "#ffffff" })
    property var cfg: defaults
    FileView {
        id: settings
        property int tries: 0
        path: Quickshell.env("HOME") + "/.config/drift/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.cfg = Object.assign({}, root.defaults, JSON.parse(text())); tries = 0 }
            catch (e) {                                   // caught halfway through being written: look again shortly
                if (++tries <= 5) again.restart()
                else console.warn("drift: settings.json is not valid JSON:", e)
            }
        }
    }
    Timer { id: again; interval: 200; onTriggered: settings.reload() }

    // what ipc.py sees: the cursor (global), the windows and the monitors
    property real cx: -9999
    property real cy: -9999
    property var wins: []
    property var mons: []
    property string focused: ""
    property real busy: 0                                 // how busy the other programs keep the processor, 0..1
    // the snow gives way: thinner when the others are busy, none at all when they are very busy
    property real give: 1
    onBusyChanged: give = busy > 0.85 ? 0 : busy > 0.6 ? 0.4 : busy < 0.45 ? 1 : give
    Process {
        id: eyes
        running: true
        command: ["python3", "-I", decodeURIComponent(Qt.resolvedUrl("ipc.py").toString().replace("file://", ""))]
        onExited: (code, status) => reopen.restart()      // should it stop, start it again shortly
        stdout: SplitParser {
            onRead: line => {
                const k = line[0], rest = line.slice(2)
                if (k === "C") { const p = rest.split(" "); root.cx = +p[0]; root.cy = +p[1] }
                else if (k === "W") root.wins = JSON.parse(rest)
                else if (k === "M") root.mons = JSON.parse(rest)
                else if (k === "F") root.focused = rest
                else if (k === "L") root.busy = +rest
            }
        }
    }

    Timer { id: reopen; interval: 2000; onTriggered: eyes.running = true }

    // the wind: gusts come and go
    property real gust: 0
    Behavior on gust { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: { interval = 4000 + Math.random() * 9000; root.gust = (Math.random() * 2 - 1) * (Math.random() < 0.3 ? 1 : 0.35) }
    }

    Variants {
        model: Quickshell.screens

        Scope {
        id: scr
        required property var modelData
        // a fullscreen window here (a video, a game) gets the screen to itself: no snow drawn over or under it
        readonly property bool hush: root.wins.some(w => w.z && w.v && w.m === modelData.name)

        // ------------------------------------------------ far snow, behind the windows
        // Nothing here moves a flake after it is made, so the graphics chip moves them all and the processor does nothing.
        PanelWindow {
            id: far
            screen: scr.modelData
            visible: !scr.hush && root.cfg.behind !== false
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom              // above the wallpaper, under every window
            WlrLayershell.namespace: "drift-back"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            ParticleSystem { id: back; anchors.fill: parent; paused: !far.visible }
            ImageParticle { system: back; groups: ["far"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.5; entryEffect: ImageParticle.Fade }
            Emitter {
                system: back; group: "far"
                x: Math.min(0, -win.drift) - win.width * 0.05; y: -24; width: win.width * 1.1 + Math.abs(win.drift); height: 1
                lifeSpan: (win.height + 60) / 22 * 1000          // long enough for the slowest to reach the bottom
                size: 3; sizeVariation: 1
                emitRate: win.width / 1000 * 9 * win.amount * root.give
                velocity: AngleDirection { angle: 90 - win.wind * 28; angleVariation: 9; magnitude: 32; magnitudeVariation: 10 }
            }
            Age {                                             // gone at the bottom; far snow doesn't pile up
                system: back
                x: 0; y: parent.height - 3; width: parent.width; height: 6
                lifeLeft: 400; once: true
            }
        }

        PanelWindow {
            id: win
            readonly property var modelData: scr.modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "drift"
            visible: !scr.hush
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}                                  // every click goes to what is under the snow

            readonly property var mon: root.mons.find(m => m.n === modelData.name) || { x: 0, y: 0 }
            readonly property real lx: root.cx - mon.x          // the cursor, on this screen
            readonly property real ly: root.cy - mon.y
            readonly property real amount: Math.max(0, +root.cfg.amount || 0)
            readonly property real wind: (+root.cfg.wind || 0) * root.gust
            readonly property string snow: root.cfg.color || "#ffffff"
            readonly property real drift: wind * width * 0.45   // how far sideways a flake goes on its way down, about

            // ------------------------------------------------ settled snow
            // a pile is a row of cells along an edge, each with a height in px
            readonly property int cell: 6
            property var piles: ({})                      // address (or "ground") -> {x, y, w, cells, max, shown}; changed in place
            property var shownPiles: []                   // the keys drawn; set only when that list changes, so the drawings stay
            signal redraw()
            property bool dirty: false                    // the piles changed: draw them again soon (a few times a second)
            property bool urgent: false                   // snow came off an edge: draw them again now

            function edges() {                            // the focused window, if it's on this screen, holds snow
                return root.wins.filter(w => w.a === root.focused && w.m === modelData.name && w.v && !w.f && w.w > 40)
                                .map(w => ({ a: w.a, x: w.x - mon.x, y: w.y - mon.y, w: w.w }))
            }
            property var tops: []

            function pileFor(a, x, y, w, max) {
                let p = piles[a]
                if (!p || p.w !== w) { p = { x: x, y: y, w: w, max: max, cells: new Array(Math.ceil(w / cell)).fill(0) }; piles[a] = p }
                p.x = x; p.y = y; p.shown = true
                return p
            }
            function spill(p, from, to) {                 // its snow falls off between two x's (all of it without them)
                const lo = from === undefined ? 0 : Math.max(0, Math.floor((from - p.x) / cell))
                const hi = to === undefined ? p.cells.length : Math.min(p.cells.length, Math.ceil((to - p.x) / cell))
                for (let i = lo; i < hi; i++) {
                    const h = p.cells[i]
                    if (h > 0.6) chunks.burst(Math.min(6, Math.ceil(h / 2.5)), p.x + i * cell, p.y - h / 2)
                    p.cells[i] = 0
                }
                dirty = urgent = true
            }
            function land(x, y) {                         // a flake came down at x on whichever edge is under it
                if (!root.cfg.settle) return
                for (const a in piles) {
                    const p = piles[a]
                    if (!p.shown || x < p.x || x >= p.x + p.w || Math.abs(y - p.y) > 12) continue
                    const i = Math.floor((x - p.x) / cell), c = p.cells
                    c[i] = Math.min(p.max, c[i] + 0.55)
                    if (i > 0) c[i - 1] = Math.min(p.max, c[i - 1] + 0.2)
                    if (i + 1 < c.length) c[i + 1] = Math.min(p.max, c[i + 1] + 0.2)
                    dirty = true
                    return
                }
            }

            onTopsChanged: {
                const seen = {}
                for (const t of tops) {
                    const old = piles[t.a]
                    if (old && old.shown && (Math.abs(old.x - t.x) > 2 || Math.abs(old.y - t.y) > 2 || old.w !== t.w)) {
                        spill(old); delete piles[t.a]          // it moved or changed size: its snow slides off
                    }
                    pileFor(t.a, t.x, t.y, t.w, 15)
                    seen[t.a] = true
                }
                const all = {}, shownHere = {}
                for (const w of root.wins) { all[w.a] = true; if (w.v && w.m === modelData.name) shownHere[w.a] = true }
                for (const a in piles) {
                    if (a === "ground" || seen[a]) continue
                    if (piles[a].shown && (!all[a] || shownHere[a])) { spill(piles[a]); delete piles[a] }   // closed, or lost focus: it slides off
                    else piles[a].shown = false                                                             // on a hidden workspace: kept
                }
                pileFor("ground", 0, height, width, 24)
                const keys = Object.keys(piles).filter(a => piles[a].shown)
                if (JSON.stringify(keys) !== JSON.stringify(shownPiles)) shownPiles = keys
                dirty = urgent = true
            }
            function look() {                             // the edges again, kept as they were when nothing about them changed
                const e = edges()
                if (JSON.stringify(e) !== JSON.stringify(tops)) tops = e
            }
            Connections { target: root; function onWinsChanged() { win.look() } function onMonsChanged() { win.look() } function onFocusedChanged() { win.look() } }
            onHeightChanged: tops = edges()
            onWidthChanged: tops = edges()
            Component.onCompleted: tops = edges()

            Timer {                                       // melting, and the cursor sweeping an edge
                interval: 100; running: true; repeat: true
                property int n: 0
                onTriggered: {
                    n++
                    if (root.cfg.cursor) {
                        for (const a in win.piles) {
                            const p = win.piles[a]
                            if (!p.shown || win.lx < p.x - 10 || win.lx > p.x + p.w + 10) continue
                            const top = Math.max(...p.cells.slice(Math.max(0, Math.floor((win.lx - p.x) / win.cell) - 4), Math.floor((win.lx - p.x) / win.cell) + 5), 0)
                            if (win.ly > p.y - top - 10 && win.ly < p.y + 4) win.spill(p, win.lx - 20, win.lx + 20)
                        }
                    }
                    if (n % 10 === 0) {
                        const m = (+root.cfg.melt || 0) * (win.amount > 0 ? 0.04 : 0.25)
                        for (const a in win.piles) win.piles[a].cells = win.piles[a].cells.map(h => Math.max(0, h - m * (0.5 + Math.random())))
                        win.dirty = true
                    }
                    if (win.dirty && (win.urgent || n % 4 === 0)) { win.dirty = win.urgent = false; win.redraw() }
                }
            }

            Repeater {                                    // drawn piles
                model: win.shownPiles
                Canvas {
                    id: drawn
                    required property string modelData
                    property var p: null
                    function place() {                    // the pile is changed in place, so look again each time
                        p = win.piles[modelData] || null
                        if (!p) return
                        x = p.x; y = p.y - p.max - 2; width = p.w; height = p.max + 2
                        requestPaint()
                    }
                    Component.onCompleted: place()
                    Connections { target: win; function onRedraw() { drawn.place() } }
                    onPaint: {
                        const g = getContext("2d"), c = p ? p.cells : [], base = height, s = win.cell
                        g.clearRect(0, 0, width, height)
                        if (!c.some(h => h > 0.3)) return
                        g.beginPath(); g.moveTo(0, base)
                        for (let i = 0; i < c.length; i++) {
                            const a = Math.max(0, (c[i - 1] ?? c[i]) + c[i] + (c[i + 1] ?? c[i])) / 3
                            g.quadraticCurveTo(i * s, base - a, i * s + s / 2, base - a)
                        }
                        g.lineTo(width, base); g.closePath()
                        const grad = g.createLinearGradient(0, 0, 0, base)
                        grad.addColorStop(0, win.snow); grad.addColorStop(1, Qt.tint(win.snow, "#55a8c8ff"))
                        g.fillStyle = grad; g.globalAlpha = 0.95; g.fill()
                    }
                }
            }

            // ------------------------------------------------ falling snow
            ParticleSystem { id: sys; anchors.fill: parent; paused: !win.visible }

            ImageParticle { system: sys; groups: ["mid"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.7; entryEffect: ImageParticle.Fade }
            ImageParticle { system: sys; groups: ["near", "chunk"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.9; entryEffect: ImageParticle.Fade }

            component Fall: Emitter {
                property real speed: 50
                property real reach: Math.abs(win.drift)
                system: sys
                x: Math.min(0, -Math.sign(win.wind) * reach) - win.width * 0.05; y: -24; width: win.width * 1.1 + reach; height: 1
                lifeSpan: (win.height + 60) / (speed * 0.7) * 1000   // long enough for the slowest to reach the ground
                velocity: AngleDirection { angle: 90 - win.wind * 28; angleVariation: 9; magnitude: speed; magnitudeVariation: speed * 0.3 }
            }
            // mid flakes keep the way they set off in, so the graphics chip moves them; the gust turns the new ones
            Fall { group: "mid";  speed: 58; size: 6;  sizeVariation: 2; emitRate: win.width / 1000 * 13 * win.amount * root.give }
            // near flakes, the few big ones, sway and blow about: these alone are moved by the processor
            Fall { group: "near"; speed: 95; size: 11; sizeVariation: 4; emitRate: win.width / 1000 * 5 * win.amount * root.give
                   reach: Math.abs(win.wind) * win.width * 0.3 + win.width * 0.2 }

            Emitter {                                     // snow coming off an edge
                id: chunks
                system: sys; group: "chunk"; enabled: false
                lifeSpan: 5000; size: 7; sizeVariation: 3
                velocity: AngleDirection { angle: 90; angleVariation: 55; magnitude: 60; magnitudeVariation: 40 }
                acceleration: PointDirection { y: 260 }
            }

            Wander { system: sys; groups: ["near"]; xVariance: 28; pace: 45 }
            Gravity { system: sys; groups: ["near"]; angle: 0; magnitude: win.wind * 30 }
            Friction { system: sys; factor: 0.8; threshold: 170 }   // touches only flakes going faster than that: pushed ones and chunks

            Attractor {                                   // flakes swirl away from the cursor
                system: sys; enabled: root.cfg.cursor
                x: win.lx - 90; y: win.ly - 90; width: 180; height: 180
                shape: EllipseShape {}
                pointX: 90; pointY: 90
                strength: -2600
                affectedParameter: Attractor.Velocity
                proportionalToDistance: Attractor.InverseLinear
            }

            Repeater {                                    // flakes stop where they land
                model: win.tops.concat([{ a: "ground", x: 0, y: win.height, w: win.width }])
                Age {
                    required property var modelData
                    system: sys; groups: ["mid", "near"]
                    x: modelData.x; y: modelData.y - 5; width: modelData.w; height: 10
                    lifeLeft: 0
                    once: true
                    onAffected: (px, py) => win.land(px, modelData.y)
                }
            }
        }
        }
    }
}

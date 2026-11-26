// drift: snow on the desktop. It falls in three depths, sways and blows in gusts, settles on the tops of
// windows and along the bottom of the screen, slides off a window that moves or closes, and parts around
// the cursor, which also sweeps settled snow off an edge. Clicks go straight through it.
import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ~/.config/drift/settings.json, read again whenever it changes
    property var cfg: ({ amount: 1.0, wind: 1.0, settle: true, cursor: true, melt: 0.3, color: "#ffffff" })
    FileView {
        path: Quickshell.env("HOME") + "/.config/drift/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.cfg = Object.assign({ amount: 1.0, wind: 1.0, settle: true, cursor: true, melt: 0.3, color: "#ffffff" }, JSON.parse(text())) }
            catch (e) { console.warn("drift: settings.json is not valid JSON:", e) }
        }
    }

    // what ipc.py sees: the cursor (global), the windows and the monitors
    property real cx: -9999
    property real cy: -9999
    property var wins: []
    property var mons: []
    Process {
        running: true
        command: ["python3", "-I", Qt.resolvedUrl("ipc.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                const k = line[0], rest = line.slice(2)
                if (k === "C") { const p = rest.split(" "); root.cx = +p[0]; root.cy = +p[1] }
                else if (k === "W") root.wins = JSON.parse(rest)
                else if (k === "M") root.mons = JSON.parse(rest)
            }
        }
    }

    // the wind: gusts come and go
    property real gust: 0
    Behavior on gust { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: { interval = 4000 + Math.random() * 9000; root.gust = (Math.random() * 2 - 1) * (Math.random() < 0.3 ? 1 : 0.35) }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "drift"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}                                  // every click goes to what is under the snow

            readonly property var mon: root.mons.find(m => m.n === modelData.name) || { x: 0, y: 0 }
            readonly property real lx: root.cx - mon.x          // the cursor, on this screen
            readonly property real ly: root.cy - mon.y
            readonly property real amount: Math.max(0, +root.cfg.amount || 0)
            readonly property real wind: (+root.cfg.wind || 0) * root.gust
            readonly property string snow: root.cfg.color || "#ffffff"

            // ------------------------------------------------ settled snow
            // a pile is a row of cells along an edge, each with a height in px
            readonly property int cell: 6
            property var piles: ({})                      // address (or "ground") -> {x, y, w, cells, max, shown}
            property bool dirty: false

            function edges() {                            // the windows on this screen whose tops hold snow
                return root.wins.filter(w => w.m === modelData.name && w.v && !w.f && w.w > 40)
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
                dirty = true
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
                const all = {}
                for (const w of root.wins) all[w.a] = true
                for (const a in piles) {
                    if (a === "ground" || seen[a]) continue
                    if (!all[a] && piles[a].shown) { spill(piles[a]); delete piles[a] }   // it closed
                    else piles[a].shown = false                                           // another workspace: kept
                }
                pileFor("ground", 0, height, width, 24)
                dirty = true
            }
            Connections { target: root; function onWinsChanged() { win.tops = win.edges() } function onMonsChanged() { win.tops = win.edges() } }
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
                    if (win.dirty) { win.dirty = false; win.pilesChanged() }
                }
            }

            Repeater {                                    // drawn piles
                model: Object.keys(win.piles).filter(a => win.piles[a].shown)
                Canvas {
                    required property string modelData
                    readonly property var p: win.piles[modelData]
                    x: p ? p.x : 0; y: p ? p.y - p.max - 2 : 0
                    width: p ? p.w : 0; height: p ? p.max + 2 : 0
                    Connections { target: win; function onPilesChanged() { requestPaint() } }
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
            ParticleSystem { id: sys; anchors.fill: parent }

            ImageParticle { system: sys; groups: ["far"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.45; entryEffect: ImageParticle.Fade }
            ImageParticle { system: sys; groups: ["mid"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.7; entryEffect: ImageParticle.Fade }
            ImageParticle { system: sys; groups: ["near", "chunk"]; source: "qrc:///particleresources/fuzzydot.png"; color: win.snow; alpha: 0.9; entryEffect: ImageParticle.Fade }

            component Fall: Emitter {
                property real speed: 50
                system: sys
                x: -win.width * 0.25; y: -24; width: win.width * 1.5; height: 1
                lifeSpan: (win.height + 60) / speed * 1600
                velocity: AngleDirection { angle: 90 - win.wind * 28; angleVariation: 9; magnitude: speed; magnitudeVariation: speed * 0.3 }
            }
            Fall { group: "far";  speed: 32; size: 3;  sizeVariation: 1; emitRate: win.width / 1000 * 22 * win.amount }
            Fall { group: "mid";  speed: 58; size: 6;  sizeVariation: 2; emitRate: win.width / 1000 * 13 * win.amount }
            Fall { group: "near"; speed: 95; size: 11; sizeVariation: 4; emitRate: win.width / 1000 * 5 * win.amount }

            Emitter {                                     // snow coming off an edge
                id: chunks
                system: sys; group: "chunk"; enabled: false
                lifeSpan: 5000; size: 7; sizeVariation: 3
                velocity: AngleDirection { angle: 90; angleVariation: 55; magnitude: 60; magnitudeVariation: 40 }
                acceleration: PointDirection { y: 260 }
            }

            Wander { system: sys; groups: ["far", "mid", "near"]; xVariance: 28; pace: 45 }
            Gravity { system: sys; groups: ["far", "mid", "near"]; angle: 0; magnitude: win.wind * 30 }
            Friction { system: sys; factor: 0.8; threshold: 170 }

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
                    system: sys; groups: ["far", "mid", "near"]
                    x: modelData.x; y: modelData.y - 5; width: modelData.w; height: 10
                    lifeLeft: 0
                    once: true
                    onAffected: (px, py) => win.land(px, modelData.y)
                }
            }
        }
    }
}

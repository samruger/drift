import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// drift (the desktop snow, github.com/samruger/drift), made like the bar's indicators (reminder, notifications,
// night light, stay awake) and placed right after them: lit while the snow falls, a click turns it on or off,
// a right click opens drift's settings. (The indicators widget only loads indicators from its own folder,
// so this is a bar module of its own that uses the same BarIndicator.)
BarIndicator {
  id: root

  property bool snowing: false
  property bool popupOpen: false

  active: snowing
  // shown dim while off, as the indicators are with alwaysShow (they get this from the indicators widget)
  indicatorHost: QtObject { readonly property bool revealInactiveIndicators: true }
  revealHost: bar
  activeText: ""
  inactiveText: ""
  activeTooltipText: "Snow: on (right click: settings)"
  inactiveTooltipText: "Snow: off (right click: settings)"

  function close() { popupOpen = false }
  function toggle() {
    root.snowing = !root.snowing
    if (root.bar) root.bar.run("drift")
    recheck.restart()
  }

  // drift keeps its pid in $XDG_RUNTIME_DIR/drift.pid; snowing = that process is alive and is drift
  Process {
    id: check
    command: ["sh", "-c", "p=$(cat \"${XDG_RUNTIME_DIR:-/tmp}/drift.pid\" 2>/dev/null); [ -n \"$p\" ] && [ \"$(cat /proc/$p/comm 2>/dev/null)\" = drift ]"]
    onExited: function(code) { root.snowing = code === 0 }
  }
  Timer {
    interval: 2000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: check.running = true
  }
  Timer { id: recheck; interval: 400; onTriggered: check.running = true }

  onPressed: function(pressedButton) {
    if (pressedButton === Qt.RightButton) { root.popupOpen = !root.popupOpen; return }
    if (pressedButton === Qt.LeftButton) root.toggle()
  }

  // qs ipc -p /usr/share/omarchy/shell call drift menu   (or: toggle) -- for a keybind
  IpcHandler {
    target: "drift"
    function menu(): void { root.popupOpen = !root.popupOpen }
    function toggle(): void { root.toggle() }
  }

  DriftCard {
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    snowing: root.snowing
    onToggleSnow: root.toggle()
  }
}

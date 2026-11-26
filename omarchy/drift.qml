import QtQuick
import Quickshell.Io
import qs.Ui

// A snowflake that turns drift (the desktop snow, github.com/samruger/drift) on and off.
// It glows icy blue while the snow is falling. Right click opens drift's settings.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool snowing: false
  property bool popupOpen: false

  function close() { popupOpen = false }
  function toggle() {
    root.snowing = !root.snowing
    root.bar.run("drift")
    recheck.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // drift keeps its pid in $XDG_RUNTIME_DIR/drift.pid; snowing = that process is alive
  Process {
    id: check
    command: ["sh", "-c", "kill -0 \"$(cat \"${XDG_RUNTIME_DIR:-/tmp}/drift.pid\" 2>/dev/null)\" 2>/dev/null"]
    onExited: function(code) { root.snowing = code === 0 }
  }
  Timer {
    interval: 2000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: check.running = true
  }
  Timer { id: recheck; interval: 400; onTriggered: check.running = true }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.snowing
    activeColor: "#a8dcff"
    tooltipText: (root.snowing ? "Snow: on" : "Snow: off") + " (right click: settings)"
    onPressed: function(pressedButton) {
      if (!root.bar) return
      if (pressedButton === Qt.RightButton) { root.popupOpen = !root.popupOpen; return }
      if (pressedButton === Qt.LeftButton) root.toggle()
    }
  }

  // qs ipc -p <the shell> call drift menu   (or: toggle) -- for a keybind
  IpcHandler {
    target: "drift"
    function menu(): void { root.popupOpen = !root.popupOpen }
    function toggle(): void { root.toggle() }
  }

  DriftCard {
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    snowing: root.snowing
    onToggleSnow: root.toggle()
  }
}

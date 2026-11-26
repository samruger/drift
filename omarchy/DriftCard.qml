import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// drift's settings, opened by right clicking the snowflake on the bar. Every change is written straight to
// ~/.config/drift/settings.json, which drift rereads as soon as it changes, so the snow follows along live.
PopupCard {
  id: card

  property bool snowing: false
  signal toggleSnow()

  readonly property var defaults: ({ amount: 1.0, wind: 1.0, settle: true, cursor: true, behind: true, melt: 0.3, color: "#ffffff" })
  property var cfg: defaults

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Util.alpha(Commons.Color.popups.text, 0.6)

  readonly property var colors: [
    { name: "White", c: "#ffffff" },
    { name: "Ice", c: "#a8dcff" },
    { name: "Frost", c: "#7fffe0" },
    { name: "Lilac", c: "#d4b8ff" },
    { name: "Pink", c: "#ffb3dc" },
    { name: "Gold", c: "#ffe28a" }
  ]

  contentWidth: card.fittedContentWidth(Style.space(300))
  contentHeight: card.fittedContentHeight(column.implicitHeight)

  function set(key, value) {
    const next = Object.assign({}, card.cfg)
    next[key] = value
    card.cfg = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  Item {
    visible: false
    FileView {
      id: settingsFile
      path: Quickshell.env("HOME") + "/.config/drift/settings.json"
      watchChanges: true
      atomicWrites: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: {
        try { card.cfg = Object.assign({}, card.defaults, JSON.parse(text())) } catch (e) { }
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: card.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  component SliderRow: Column {
    id: sr
    property string title: ""
    property string key: ""
    property real maximum: 2
    property var describe: v => ""
    readonly property real value: +card.cfg[key] || 0
    width: column.width
    spacing: Style.space(2)
    Item {
      width: parent.width
      height: srTitle.implicitHeight
      Label { id: srTitle; text: sr.title }
      Label { anchors.right: parent.right; text: sr.describe(slider.liveValue); color: card.dim }
    }
    PanelSlider {
      id: slider
      bar: card.bar
      width: parent.width
      height: Style.space(22)
      minimum: 0; maximum: sr.maximum; step: 0.05
      value: sr.value
      onReleased: function(v) { card.set(sr.key, Math.round(v * 100) / 100) }
    }
  }

  Column {
    id: column
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: Style.space(8)

    Label { text: "Drift"; font.bold: true }

    Toggle {
      width: column.width
      label: "Snow"
      description: card.snowing ? "Falling" : "Off"
      checked: card.snowing
      onClicked: card.toggleSnow()
    }
    Toggle {
      width: column.width
      label: "Pile up"
      description: card.cfg.settle ? "Snow collects on the focused window and the ground" : "Snow falls straight through"
      checked: !!card.cfg.settle
      onClicked: card.set("settle", !card.cfg.settle)
    }
    Toggle {
      width: column.width
      label: "Mouse"
      description: card.cfg.cursor ? "Pushes flakes and sweeps piles" : "Snow ignores the mouse"
      checked: !!card.cfg.cursor
      onClicked: card.set("cursor", !card.cfg.cursor)
    }
    Toggle {
      width: column.width
      label: "Behind windows"
      description: card.cfg.behind !== false ? "Far snow falls behind the windows too" : "Off: lighter on the processor"
      checked: card.cfg.behind !== false
      onClicked: card.set("behind", card.cfg.behind === false)
    }

    SliderRow {
      title: "Amount"; key: "amount"; maximum: 3
      describe: v => v < 0.05 ? "none" : v < 0.6 ? "light" : v < 1.4 ? "normal" : v < 2.2 ? "heavy" : "blizzard"
    }
    SliderRow {
      title: "Wind"; key: "wind"; maximum: 3
      describe: v => v < 0.05 ? "still" : v < 0.6 ? "breeze" : v < 1.4 ? "gusty" : v < 2.2 ? "windy" : "gale"
    }
    SliderRow {
      title: "Melt"; key: "melt"; maximum: 2
      describe: v => v < 0.05 ? "never" : v < 0.5 ? "slow" : v < 1.2 ? "medium" : "fast"
    }

    Label { text: "Color" }
    Row {
      spacing: Style.space(8)
      Repeater {
        model: card.colors
        Rectangle {
          required property var modelData
          width: Style.space(28); height: width; radius: width / 2
          color: modelData.c
          border.width: String(card.cfg.color).toLowerCase() === modelData.c ? 3 : 1
          border.color: String(card.cfg.color).toLowerCase() === modelData.c ? Commons.Color.accent : Util.alpha(card.fg, 0.3)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: card.set("color", parent.modelData.c)
          }
        }
      }
    }
  }
}

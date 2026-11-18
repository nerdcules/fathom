import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."
import "Version.js" as Build
import "Format.js" as F

// The Command Deck at a glance, in the bar: containers that need attention,
// Care's warnings, a disk filling up, Sentinel's alerts and the coding agents
// at work. Only what's worth a glance shows; with nothing to say it shows the
// deck's mark alone. Click opens the deck page with the worst news, right-
// click opens the deck, middle-click Start.
//
// It asks `fathom-deck brief` every few seconds (no CPU sampling unless an
// agent other than Claude Code is running; Care and Sentinel are asked only
// what they already know), so it reads the machine in the background, unlike
// the deck itself.
//
// Settings (shell.json layout entry): interval (seconds between readings,
// default 10, at least 3).
BarWidget {
  id: root
  moduleName: "fathom.deck"

  readonly property string deckTool: Quickshell.env("HOME") + "/.local/bin/fathom-deck"
  readonly property int interval: Math.max(3, Number(setting("interval", 10)) || 10)

  property var brief: null
  readonly property var segments: F.barSegments(brief)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function toneColor(tone) {
    if (tone === "bad") return Commons.Color.urgent
    if (tone === "warn") return "#ffb547"
    if (tone === "busy") return Commons.Color.accent
    return button.foreground
  }

  function summon(page) {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "fathom.deck", JSON.stringify({ page: page })])
  }

  function line(seg) {
    var b = brief || {}
    if (seg.key === "docker") {
      return seg.tone === "bad"
        ? strings.tn("bar.containersBad", seg.n).arg(seg.n)
        : strings.t("bar.containers").arg(seg.n).arg((b.docker && b.docker.total) || seg.n)
    }
    if (seg.key === "care") return strings.tn("bar.warnings", seg.n).arg(seg.n)
    if (seg.key === "disk") return strings.t("bar.disk").arg(seg.n)
    if (seg.key === "sentinel") return strings.tn("bar.alerts", seg.n).arg(seg.n)
    if (seg.key === "agents") {
      var list = (b.agents && Array.isArray(b.agents.list)) ? b.agents.list : []
      var head = seg.tone === "busy" ? strings.tn("bar.agentsWorking", seg.n).arg(seg.n) : strings.tn("bar.agentsIdle", seg.n).arg(seg.n)
      var rows = []
      for (var i = 0; i < list.length && i < 6; i++) {
        var a = list[i]
        rows.push("  " + String(a.name || "") + (a.folder ? " · " + String(a.folder) : "")
          + " · " + (a.working ? strings.t("bar.working") : strings.t("bar.idle")))
      }
      return [head].concat(rows).join("\n")
    }
    return ""
  }

  readonly property string tooltip: {
    var lines = []
    if (!brief) lines.push(strings.t("loading"))
    else if (segments.length === 0) lines.push(strings.t("bar.quiet"))
    for (var i = 0; i < segments.length; i++) lines.push(line(segments[i]))
    lines.push(strings.t("bar.hint"))
    lines.push("Fathom " + Build.text)
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: [root.deckTool, "brief"]
    stdout: StdioCollector {
      onStreamFinished: {
        // An odd answer keeps the last good one.
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object" && parsed.docker) root.brief = parsed
        } catch (e) {}
      }
    }
    onExited: pause.restart()
  }

  // The next reading starts a while after the last one finished.
  Timer {
    id: pause
    interval: root.interval * 1000
    onTriggered: if (!proc.running) proc.running = true
  }
  Component.onCompleted: proc.running = true

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 10
    fixedWidth: root.vertical ? -1 : row.implicitWidth + Style.spaceReal(horizontalMargin) * 2
    fixedHeight: root.vertical ? row.implicitHeight + Style.spaceReal(verticalPadding) * 2 : -1
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.summon("deck")
      else if (b === Qt.MiddleButton) root.summon("start")
      else root.summon(F.barPage(root.segments))
    }

    Grid {
      id: row
      anchors.centerIn: parent
      flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
      columns: root.vertical ? 1 : Math.max(1, root.segments.length)
      rows: root.vertical ? Math.max(1, root.segments.length) : 1
      columnSpacing: Style.spaceReal(9)
      rowSpacing: Style.spaceReal(4)
      scale: button.pressScale

      // The deck's mark, when there's nothing to count.
      Label {
        visible: root.segments.length === 0
        text: "\uf0e4"
        elide: Text.ElideNone
        color: button.foreground
        opacity: 0.75
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.segments
        delegate: Label {
          required property var modelData
          elide: Text.ElideNone
          // Glyph and count; a vertical bar has room only for the glyph
          // over a short number.
          text: modelData.glyph + (root.vertical ? "\n" : " ") + modelData.n + (modelData.key === "disk" ? "%" : "")
          horizontalAlignment: Text.AlignHCenter
          color: root.toneColor(modelData.tone)
          opacity: modelData.tone === "quiet" ? 0.75 : 1
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          font.weight: modelData.tone === "bad" ? Font.DemiBold : Font.Normal
          renderType: Text.NativeRendering
        }
      }
    }
  }
}

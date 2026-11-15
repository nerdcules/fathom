import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "."
import "Format.js" as F

// The Pulse page: a map of what calls what, from `fathom-pulse status`, and
// an inspector for the node you pick.
GridLayout {
  id: page

  property var pulse: null
  // "15m", "1h" or "24h".
  property string range: "15m"

  signal rangeRequested(string range)
  signal askRequested(string text)

  readonly property bool running: !!pulse && pulse.running === true
  readonly property var nodes: running && Array.isArray(pulse.nodes) ? pulse.nodes : []
  readonly property var edges: running && Array.isArray(pulse.edges) ? pulse.edges : []
  readonly property var errors: running && Array.isArray(pulse.errors) ? pulse.errors : []
  readonly property var problem: running ? F.pulseProblems(pulse.problems) : null
  readonly property int services: {
    var n = 0
    for (var i = 0; i < nodes.length; i++) if (nodes[i].kind === "service") n++
    return n
  }
  readonly property int errorCount: {
    var n = 0
    for (var i = 0; i < nodes.length; i++) if (nodes[i].kind === "service") n += nodes[i].errors || 0
    return n
  }

  // The node the inspector shows: the one picked, while it's on the map,
  // else the busiest service.
  property string picked: ""
  readonly property var selected: {
    var first = null
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].id === picked) return nodes[i]
      if (!first) first = nodes[i]
    }
    return first
  }

  // One line of an inspector list: a dot, a name, and a figure.
  component MiniRow: Item {
    id: mini
    property color tone: Skin.ok
    property string name: ""
    property string figure: ""
    property bool clickable: false
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: 26 * Skin.u
    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -4 * Skin.u
      anchors.rightMargin: -4 * Skin.u
      radius: 8 * Skin.u
      color: mini.clickable && miniHover.hovered ? Skin.faint : "transparent"
    }
    HoverHandler { id: miniHover; cursorShape: mini.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: mini.clickable; onTapped: mini.clicked() }
    RowLayout {
      anchors.fill: parent
      spacing: 10 * Skin.u
      Dot { tone: mini.tone }
      Label { text: mini.name; font.pixelSize: 13 * Skin.u; Layout.fillWidth: true }
      Label { text: mini.figure; color: Skin.dim; font.pixelSize: 12 * Skin.u }
    }
  }

  columns: 2
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  function rateText(perSecond) {
    var r = F.pulseRate(perSecond)
    return Skin.t("pulse.rate." + r.unit).arg(Skin.n(r.value, r.decimals))
  }
  function msText(ms) {
    var m = F.pulseMs(ms)
    return m ? Skin.t("pulse.ms." + m.unit).arg(Skin.n(m.value, m.decimals)) : Skin.t("pulse.none")
  }
  function figuresText(n) {
    if (!n || !n.count) return ""
    return rateText(n.rate) + "  ·  " + Skin.t("pulse.p95").arg(msText(n.p95ms))
  }
  function nameOf(id) {
    for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i].name
    return String(id).replace(/^[a-z]+:/, "")
  }
  function glyphFor(kind) {
    return { database: "", ai: "", messaging: "", external: "" }[kind] || ""
  }
  function clock(t) {
    return new Date(t * 1000).toLocaleTimeString(Skin.locale, "HH:mm")
  }

  function summary() {
    if (!pulse) return [{ tone: "stopped", text: Skin.t("loading") }]
    if (!running) return [{ tone: "bad", text: Skin.t("pulse.notRunning") }]
    if (nodes.length === 0) return [{ tone: "stopped", text: Skin.t("pulse.waiting") }]
    var out = [{ tone: "ok", text: Skin.tn("pulse.summary.services", services).arg(Skin.n(services)) }]
    if (errorCount > 0) out.push({ tone: "warn", text: Skin.tn("pulse.summary.errors", errorCount).arg(Skin.n(errorCount)).arg(Skin.t("pulse.range." + range)) })
    else out.push({ tone: "ok", text: Skin.t("pulse.summary.noErrors").arg(Skin.t("pulse.range." + range)) })
    return out
  }

  // ------------------------------------------------ the map
  Card {
    Layout.preferredWidth: 2.2
    title: Skin.t("pulse.title")
    glyph: ""
    subtitle: page.running && page.pulse.dropped > 0
      ? Skin.tn("pulse.dropped", page.pulse.dropped).arg(Skin.n(page.pulse.dropped)) : ""
    subtitleColor: Skin.warn

    RowLayout {
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      Repeater {
        model: ["15m", "1h", "24h"]
        delegate: Pill {
          required property string modelData
          text: Skin.t("pulse.range." + modelData)
          selected: page.range === modelData
          onClicked: page.rangeRequested(modelData)
        }
      }
      Item { Layout.fillWidth: true }
      Label {
        visible: page.running
        text: page.running ? Skin.t("pulse.listening").arg(page.pulse.ports.grpc).arg(page.pulse.ports.http) : ""
        color: Skin.dim
        font.pixelSize: 12 * Skin.u
      }
    }

    Empty {
      visible: !!page.pulse && !page.running
      text: Skin.t("pulse.notRunningDetail")
      color: Skin.warn
    }
    Label {
      visible: !!page.problem
      text: page.problem ? Skin.t("pulse.problem").arg(page.problem.where).arg(page.problem.reason) : ""
      color: Skin.warn
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }
    Empty {
      visible: page.running && page.nodes.length === 0
      text: Skin.t("pulse.waitingDetail").arg(page.running ? page.pulse.ports.grpc : 4317).arg(page.running ? page.pulse.ports.http : 4318)
    }

    Item {
      id: map
      visible: page.nodes.length > 0
      Layout.fillWidth: true
      readonly property int rows: {
        var n = 1
        for (var i = 0; i < layout.length; i++) n = Math.max(n, layout[i].ids.length + (layout[i].hidden > 0 ? 1 : 0))
        return n
      }
      Layout.preferredHeight: Math.max(300 * Skin.u, rows * (boxH + gap) + gap)
      readonly property real boxW: Math.min(230 * Skin.u, width / Math.max(1, layout.length * 1.3))
      readonly property real boxH: 64 * Skin.u
      readonly property real gap: 22 * Skin.u
      readonly property var layout: F.pulseLayout(page.nodes, page.edges, 6)
      readonly property var pos: F.pulsePositions(layout, width, height, boxW, boxH, gap)
      // Distance from one column's left edge to the next.
      readonly property real step: layout.length > 1 ? (width - boxW) / (layout.length - 1) : width

      // Edges first, under the boxes.
      Repeater {
        model: page.edges
        delegate: Item {
          id: edge
          required property var modelData
          readonly property var a: map.pos[modelData.from]
          readonly property var b: map.pos[modelData.to]
          readonly property string health: F.pulseHealth(modelData.errorRate, modelData.count)
          readonly property bool lit: !!page.selected && (modelData.from === page.selected.id || modelData.to === page.selected.id)
          visible: !!a && !!b && modelData.from !== modelData.to
          anchors.fill: parent

          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "transparent"
              strokeColor: edge.health === "bad" ? Skin.urgent : (edge.health === "warn" ? Skin.warn
                : (edge.lit ? Skin.accent : Skin.tint(Skin.fg, 0.28)))
              strokeWidth: (edge.lit ? 2.2 : 1.4) * Skin.u
              startX: edge.a ? edge.a.x + map.boxW : 0
              startY: edge.a ? edge.a.y + map.boxH / 2 : 0
              PathCubic {
                x: edge.b ? edge.b.x : 0
                y: edge.b ? edge.b.y + map.boxH / 2 : 0
                readonly property real bend: edge.a && edge.b ? Math.max(40 * Skin.u, Math.abs(edge.b.x - edge.a.x - map.boxW) / 2) : 0
                control1X: (edge.a ? edge.a.x + map.boxW : 0) + bend
                control1Y: edge.a ? edge.a.y + map.boxH / 2 : 0
                control2X: (edge.b ? edge.b.x : 0) - bend
                control2Y: edge.b ? edge.b.y + map.boxH / 2 : 0
              }
            }
          }
        }
      }

      // Call rates, drawn after every line so no line crosses a label.
      Repeater {
        model: page.edges
        delegate: Item {
          id: edge
          required property var modelData
          readonly property var a: map.pos[modelData.from]
          readonly property var b: map.pos[modelData.to]
          readonly property string health: F.pulseHealth(modelData.errorRate, modelData.count)
          visible: !!a && !!b && modelData.from !== modelData.to
          anchors.fill: parent

          // The call rate, in the gap just before the target. A line that
          // spans one gap gets it halfway along; one that skips columns, level
          // with its target, clear of the boxes it passes behind.
          Rectangle {
            readonly property bool skips: !!edge.a && !!edge.b && edge.b.x - edge.a.x > map.step * 1.5
            visible: edge.visible && edge.modelData.count > 0
            x: edge.a && edge.b ? edge.b.x - (map.step - map.boxW) / 2 - width / 2 : 0
            y: edge.a && edge.b ? (skips ? edge.b.y + map.boxH / 2 : (edge.a.y + edge.b.y + map.boxH) / 2) - height / 2 : 0
            width: rateLabel.implicitWidth + 10 * Skin.u
            height: rateLabel.implicitHeight + 4 * Skin.u
            radius: height / 2
            color: Skin.tint(Skin.bg, 0.9)
            Label {
              id: rateLabel
              anchors.centerIn: parent
              text: page.rateText(edge.modelData.rate)
              color: edge.health === "ok" || edge.health === "idle" ? Skin.dim : Skin.levelColor(edge.health)
              font.pixelSize: 11 * Skin.u
            }
          }
        }
      }

      // The boxes.
      Repeater {
        model: page.nodes
        delegate: Rectangle {
          id: box
          required property var modelData
          readonly property var p: map.pos[modelData.id]
          readonly property string health: F.pulseHealth(modelData.errorRate, modelData.count)
          readonly property bool isSelected: !!page.selected && page.selected.id === modelData.id
          visible: !!p
          x: p ? p.x : 0
          y: p ? p.y : 0
          width: map.boxW
          height: map.boxH
          radius: 12 * Skin.u
          // Opaque, so a line that skips a column passes behind the box.
          color: Qt.tint(Skin.bg, isSelected ? Skin.tint(Skin.accent, 0.16)
            : (modelData.kind === "service" ? Skin.tint(Skin.fg, 0.03) : Skin.tint(Skin.violet, 0.10)))
          border.width: (isSelected ? 2 : 1) * Skin.u
          border.color: health === "bad" ? Skin.urgent : (health === "warn" ? Skin.warn
            : (isSelected ? Skin.accent : (modelData.kind === "service" ? Skin.tint(Skin.accent, 0.35) : Skin.tint(Skin.violet, 0.45))))
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.name
          Keys.onReturnPressed: page.picked = modelData.id
          Keys.onSpacePressed: page.picked = modelData.id

          Column {
            anchors.fill: parent
            anchors.leftMargin: 12 * Skin.u
            anchors.rightMargin: 12 * Skin.u
            anchors.topMargin: 10 * Skin.u
            spacing: 3 * Skin.u
            RowLayout {
              width: parent.width
              spacing: 6 * Skin.u
              Label {
                text: box.modelData.name
                font.weight: Font.DemiBold
                Layout.fillWidth: true
              }
              Label {
                visible: text !== ""
                text: page.glyphFor(box.modelData.kind)
                color: Skin.violet
                font.pixelSize: 13 * Skin.u
              }
            }
            Label {
              width: parent.width
              text: box.modelData.count > 0 ? page.figuresText(box.modelData) : (box.modelData.detail || Skin.t("pulse.noRequests"))
              color: box.health === "bad" || box.health === "warn" ? Skin.levelColor(box.health) : Skin.dim
              font.pixelSize: 11 * Skin.u
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.picked = box.modelData.id
          }
        }
      }

      // "+3 more" under a full column.
      Repeater {
        model: map.layout
        delegate: Label {
          required property var modelData
          required property int index
          visible: modelData.hidden > 0
          readonly property var last: modelData.ids.length ? map.pos[modelData.ids[modelData.ids.length - 1]] : null
          x: last ? last.x : 0
          y: last ? last.y + map.boxH + 6 * Skin.u : 0
          width: map.boxW
          horizontalAlignment: Text.AlignHCenter
          text: Skin.tn("pulse.more", modelData.hidden).arg(Skin.n(modelData.hidden))
          color: Skin.dim
          font.pixelSize: 12 * Skin.u
        }
      }
    }

    Label {
      visible: page.running && !page.pulse.exact && page.nodes.length > 0
      text: Skin.t("pulse.dayApprox")
      color: Skin.dim
      font.pixelSize: 11 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }
  }

  // ------------------------------------------------ the inspector
  Card {
    Layout.preferredWidth: 1
    title: page.selected ? page.selected.name : Skin.t("pulse.inspector")
    glyph: page.selected ? (page.glyphFor(page.selected.kind) || "") : ""
    subtitle: page.selected ? Skin.t("pulse.kind." + page.selected.kind) + (page.selected.inferred ? " · " + Skin.t("pulse.inferred") : "") : ""

    Empty {
      visible: !page.selected
      text: Skin.t("pulse.pickOne")
    }

    Label {
      visible: !!page.selected && !!page.selected.detail
      text: page.selected ? page.selected.detail || "" : ""
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      Layout.fillWidth: true
    }

    // Three figures side by side.
    RowLayout {
      visible: !!page.selected
      Layout.fillWidth: true
      spacing: 10 * Skin.u
      Repeater {
        model: page.selected ? [
          { label: Skin.t("pulse.fig.rate"), value: page.rateText(page.selected.rate), tone: "ok" },
          { label: Skin.t("pulse.fig.p95"), value: page.msText(page.selected.p95ms), tone: "ok" },
          { label: Skin.t("pulse.fig.errors"), value: Skin.n(page.selected.errors || 0),
            tone: F.pulseHealth(page.selected.errorRate, page.selected.count) }
        ] : []
        delegate: Rectangle {
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: figure.implicitHeight + 20 * Skin.u
          radius: 12 * Skin.u
          color: Skin.faint
          Column {
            id: figure
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12 * Skin.u
            spacing: 2 * Skin.u
            SectionTitle { width: parent.width; text: modelData.label }
            Label {
              width: parent.width
              text: modelData.value
              font.pixelSize: 20 * Skin.u
              color: modelData.tone === "bad" || modelData.tone === "warn" ? Skin.levelColor(modelData.tone) : Skin.fg
            }
          }
        }
      }
    }

    SectionTitle {
      visible: !!page.selected && Array.isArray(page.selected.operations) && page.selected.operations.length > 0
      text: Skin.t("pulse.operations")
    }
    Repeater {
      model: page.selected && Array.isArray(page.selected.operations) ? page.selected.operations.slice(0, 3) : []
      delegate: MiniRow {
        required property var modelData
        tone: Skin.levelColor(F.pulseHealth(modelData.errorRate, modelData.count))
        name: modelData.name
        figure: page.rateText(modelData.rate) + "  ·  " + page.msText(modelData.p95ms)
      }
    }

    SectionTitle {
      visible: callers.count > 0
      text: Skin.t("pulse.calledBy")
    }
    Repeater {
      id: callers
      model: page.selected ? page.edges.filter(function(e) { return e.to === page.selected.id }) : []
      delegate: MiniRow {
        required property var modelData
        tone: Skin.levelColor(F.pulseHealth(modelData.errorRate, modelData.count))
        name: page.nameOf(modelData.from)
        figure: page.rateText(modelData.rate) + "  ·  " + (modelData.errors > 0
          ? Skin.tn("pulse.errorsShort", modelData.errors).arg(Skin.n(modelData.errors)) : page.msText(modelData.p95ms))
        clickable: true
        onClicked: page.picked = modelData.from
      }
    }

    SectionTitle {
      visible: callees.count > 0
      text: Skin.t("pulse.calls")
    }
    Repeater {
      id: callees
      model: page.selected ? page.edges.filter(function(e) { return e.from === page.selected.id }) : []
      delegate: MiniRow {
        required property var modelData
        tone: Skin.levelColor(F.pulseHealth(modelData.errorRate, modelData.count))
        name: page.nameOf(modelData.to)
        figure: page.rateText(modelData.rate) + "  ·  " + (modelData.errors > 0
          ? Skin.tn("pulse.errorsShort", modelData.errors).arg(Skin.n(modelData.errors)) : page.msText(modelData.p95ms))
        clickable: true
        onClicked: page.picked = modelData.to
      }
    }

    SectionTitle {
      visible: recent.count > 0
      text: Skin.t("pulse.recentErrors")
    }
    Repeater {
      id: recent
      model: page.selected ? page.errors.filter(function(e) { return page.selected.id === "svc:" + e.service }).slice(0, 4) : []
      delegate: ListRow {
        required property var modelData
        tone: Skin.urgent
        name: page.clock(modelData.time) + "  " + modelData.name
        detail: modelData.message
      }
    }

    footer: [
      Pill {
        visible: !!page.selected && page.selected.count > 0
        glyph: "✦"
        text: Skin.t("pulse.ask")
        tip: Skin.t("pulse.askTip")
        onClicked: page.askRequested(F.pulseAskText(page.selected, page.edges, page.errors, page.range))
      },
      Item { Layout.fillWidth: true }
    ]
  }
}

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

  // `fathom-pulse agents`: what Claude Code did today, by project.
  property var agents: null
  // Wide: the inspector to the right of the map and agents. Narrow: the
  // map across the top, agents and the inspector side by side below it.
  property bool wide: true

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

  readonly property var agentProjects: agents && Array.isArray(agents.projects) ? agents.projects : []
  readonly property var axis: agents ? F.agentsAxis(agentProjects, agents.start, agents.time) : null

  // The inspector shows a project from the agents card when one is picked,
  // else the node picked on the map while it's there, else the busiest
  // service.
  property string picked: ""
  property string pickedProject: ""
  readonly property var project: {
    for (var i = 0; i < agentProjects.length; i++) if (agentProjects[i].id === pickedProject) return agentProjects[i]
    return null
  }
  function pickNode(id) { pickedProject = ""; picked = id }
  function pickProject(id) { pickedProject = id }
  readonly property var selected: {
    if (project) return null
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
    MouseArea { anchors.fill: parent; enabled: mini.clickable; onClicked: mini.clicked() }
    RowLayout {
      anchors.fill: parent
      spacing: 10 * Skin.u
      Dot { tone: mini.tone }
      Label { text: mini.name; font.pixelSize: 13 * Skin.u; Layout.fillWidth: true }
      Label { text: mini.figure; color: Skin.dim; font.pixelSize: 12 * Skin.u }
    }
  }

  columns: 2   // always; `wide` decides how the cards sit in them
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

  function durText(seconds) {
    var d = F.agentsDuration(seconds)
    var t = Skin.t("pulse.agents.dur." + d.unit)
    return d.unit === "hm" ? t.arg(d.h).arg(d.m) : (d.unit === "h" ? t.arg(d.h) : (d.unit === "m" ? t.arg(d.m) : t))
  }
  function stateColor(state) {
    return state === "working" ? Skin.accent : (state === "waiting" ? Skin.warn : Skin.faint)
  }

  // "Claude is waiting for you in fathom": waiting first, since it needs you.
  function agentsSummary() {
    var out = []
    var states = ["waiting", "working"]
    for (var s = 0; s < states.length; s++) {
      var these = agentProjects.filter(function(p) { return p.state === states[s] })
      if (!these.length) continue
      var key = states[s] === "waiting" ? "pulse.agents.summaryWaiting" : "pulse.agents.summaryWorking"
      out.push({ tone: states[s] === "waiting" ? "warn" : "ok",
                 text: Skin.tn(key, these.length).arg(these.length === 1 ? these[0].name : Skin.n(these.length)) })
    }
    return out
  }

  function summary() {
    var agentLines = agentsSummary()
    if (!pulse) return [{ tone: "stopped", text: Skin.t("loading") }].concat(agentLines)
    if (!running) return [{ tone: "bad", text: Skin.t("pulse.notRunning") }].concat(agentLines)
    if (nodes.length === 0) return [{ tone: "stopped", text: Skin.t("pulse.waiting") }].concat(agentLines)
    var out = [{ tone: "ok", text: Skin.tn("pulse.summary.services", services).arg(Skin.n(services)) }]
    if (errorCount > 0) out.push({ tone: "warn", text: Skin.tn("pulse.summary.errors", errorCount).arg(Skin.n(errorCount)).arg(Skin.t("pulse.range." + range)) })
    else out.push({ tone: "ok", text: Skin.t("pulse.summary.noErrors").arg(Skin.t("pulse.range." + range)) })
    return agentLines.filter(function(l) { return l.tone === "warn" }).concat(out, agentLines.filter(function(l) { return l.tone !== "warn" }))
  }

  // ------------------------------------------------ the map
  Card {
    Layout.row: 0
    Layout.column: 0
    Layout.columnSpan: page.wide ? 1 : 2
    Layout.preferredWidth: 2.2
    // The map keeps its height; the agents card below takes what's left.
    Layout.minimumHeight: implicitHeight
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
          Keys.onReturnPressed: page.pickNode(modelData.id)
          Keys.onSpacePressed: page.pickNode(modelData.id)

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
            onClicked: page.pickNode(box.modelData.id)
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

  // ------------------------------------------------ agents today
  Card {
    id: agentsCard
    Layout.row: 1
    Layout.column: 0
    Layout.preferredWidth: page.wide ? 2.2 : 1
    Layout.fillHeight: true
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: implicitHeight
    Layout.minimumHeight: Math.min(implicitHeight, 170 * Skin.u)
    visible: !!page.agents
    title: Skin.t("pulse.agents.title")
    glyph: "\uf120"
    readonly property real nameW: 150 * Skin.u
    readonly property real totalW: 84 * Skin.u
    readonly property int maxRows: 5

    Empty {
      visible: !!page.agents && page.agents.found === false
      text: Skin.t("pulse.agents.notFound")
    }
    Empty {
      visible: !!page.agents && page.agents.found !== false && page.agentProjects.length === 0
      text: Skin.t("pulse.agents.none")
    }

    // One row per project, most recent first.
    Repeater {
      model: page.agentProjects.slice(0, agentsCard.maxRows)
      delegate: Item {
        id: agentRow
        required property var modelData
        readonly property bool isPicked: !!page.project && page.project.id === modelData.id
        Layout.fillWidth: true
        implicitHeight: 24 * Skin.u
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: modelData.name
        Keys.onReturnPressed: page.pickProject(modelData.id)
        Keys.onSpacePressed: page.pickProject(modelData.id)

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -6 * Skin.u
          anchors.rightMargin: -6 * Skin.u
          radius: 8 * Skin.u
          color: agentRow.isPicked ? Skin.tint(Skin.accent, 0.14) : (rowHover.hovered ? Skin.faint : "transparent")
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: page.pickProject(agentRow.modelData.id) }

        RowLayout {
          anchors.fill: parent
          spacing: 0
          RowLayout {
            Layout.preferredWidth: agentsCard.nameW
            Layout.maximumWidth: agentsCard.nameW
            spacing: 8 * Skin.u
            Dot { tone: page.stateColor(agentRow.modelData.state) }
            Label {
              text: agentRow.modelData.name
              font.pixelSize: 13 * Skin.u
              font.weight: agentRow.isPicked ? Font.DemiBold : Font.Normal
              Layout.fillWidth: true
            }
          }
          // The day so far.
          Item {
            id: bar
            Layout.fillWidth: true
            Layout.preferredHeight: 12 * Skin.u
            Rectangle { anchors.fill: parent; radius: 3 * Skin.u; color: Skin.tint(Skin.fg, 0.05) }
            Repeater {
              model: page.axis ? F.agentsSegments(agentRow.modelData.spans, page.axis.from, page.axis.to) : []
              delegate: Rectangle {
                required property var modelData
                x: modelData.left * bar.width
                width: Math.max(2 * Skin.u, modelData.width * bar.width)
                height: bar.height
                radius: 2 * Skin.u
                color: page.stateColor(modelData.state)
              }
            }
          }
          Label {
            Layout.preferredWidth: agentsCard.totalW
            horizontalAlignment: Text.AlignRight
            text: agentRow.modelData.working > 0 ? page.durText(agentRow.modelData.working) : ""
            color: Skin.dim
            font.pixelSize: 12 * Skin.u
          }
        }
      }
    }

    Label {
      visible: page.agentProjects.length > agentsCard.maxRows
      text: Skin.tn("pulse.agents.more", page.agentProjects.length - agentsCard.maxRows).arg(Skin.n(page.agentProjects.length - agentsCard.maxRows))
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
    }

    // The hours along the bottom.
    RowLayout {
      visible: page.agentProjects.length > 0 && !!page.axis
      Layout.fillWidth: true
      spacing: 0
      Item { Layout.preferredWidth: agentsCard.nameW }
      Item {
        id: hours
        Layout.fillWidth: true
        implicitHeight: 16 * Skin.u
        Repeater {
          model: page.axis ? page.axis.ticks : []
          delegate: Label {
            required property var modelData
            x: (modelData - page.axis.from) / (page.axis.to - page.axis.from) * hours.width - width / 2
            text: page.clock(modelData)
            color: Skin.dim
            font.pixelSize: 11 * Skin.u
          }
        }
        Label {
          anchors.right: parent.right
          text: Skin.t("pulse.agents.now")
          color: Skin.dim
          font.pixelSize: 11 * Skin.u
        }
      }
      Item { Layout.preferredWidth: agentsCard.totalW }
    }

    // The key, and what the gaps mean.
    RowLayout {
      visible: page.agentProjects.length > 0
      Layout.fillWidth: true
      spacing: 6 * Skin.u
      Repeater {
        model: ["working", "waiting"]
        delegate: RowLayout {
          required property string modelData
          spacing: 6 * Skin.u
          Layout.alignment: Qt.AlignTop
          Rectangle { width: 10 * Skin.u; height: 10 * Skin.u; radius: 3 * Skin.u; color: page.stateColor(modelData) }
          Label { text: Skin.t("pulse.agents." + modelData); color: Skin.dim; font.pixelSize: 11 * Skin.u; Layout.rightMargin: 8 * Skin.u }
        }
      }
      Label {
        text: Skin.t("pulse.agents.idleNote").arg(page.agents ? Math.round(page.agents.idleAfter / 60) : 10)
        color: Skin.dim
        font.pixelSize: 11 * Skin.u
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        Layout.fillWidth: true
      }
    }
  }

  // ------------------------------------------------ the inspector
  Card {
    Layout.row: page.wide ? 0 : 1
    Layout.column: 1
    Layout.rowSpan: page.wide ? 2 : 1
    Layout.preferredWidth: 1
    title: page.project ? page.project.name : (page.selected ? page.selected.name : Skin.t("pulse.inspector"))
    glyph: page.project ? "\uf120" : (page.selected ? (page.glyphFor(page.selected.kind) || "") : "")
    subtitle: page.project ? (page.project.state === "waiting" && page.project.waitingSince
        ? Skin.t("pulse.agents.waitingSince").arg(page.clock(page.project.waitingSince))
        : Skin.t("pulse.agents.state." + page.project.state))
      : (page.selected ? Skin.t("pulse.kind." + page.selected.kind) + (page.selected.inferred ? " · " + Skin.t("pulse.inferred") : "") : "")
    subtitleColor: page.project && page.project.state !== "idle" ? page.stateColor(page.project.state) : Skin.dim

    Empty {
      visible: !page.selected && !page.project
      text: Skin.t("pulse.pickOne")
    }

    Label {
      visible: !!page.project
      text: page.project ? page.project.path : ""
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      Layout.fillWidth: true
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
      visible: !!page.selected || !!page.project
      Layout.fillWidth: true
      spacing: 10 * Skin.u
      Repeater {
        model: page.project ? [
          { label: Skin.t("pulse.agents.fig.working"), value: page.durText(page.project.working), tone: "ok" },
          { label: Skin.t("pulse.agents.fig.waiting"), value: page.durText(page.project.waiting), tone: "ok" },
          { label: Skin.t("pulse.agents.fig.prompts"), value: Skin.n(page.project.prompts || 0), tone: "ok" }
        ] : page.selected ? [
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
              // "1 h 38 min" in a narrow tile: smaller rather than cut off.
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: 12 * Skin.u
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
        onClicked: page.pickNode(modelData.from)
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
        onClicked: page.pickNode(modelData.to)
      }
    }

    SectionTitle {
      visible: !!page.project
      text: Skin.t("pulse.agents.did")
    }
    Repeater {
      model: page.project ? [
        { name: Skin.t("pulse.agents.edits"),
          figure: Skin.tn("pulse.agents.editsFigure", page.project.files).arg(Skin.n(page.project.edits)).arg(Skin.n(page.project.files)) },
        { name: Skin.t("pulse.agents.commands"),
          figure: Skin.tn("pulse.agents.commandsFigure", page.project.tests).arg(Skin.n(page.project.commands)).arg(Skin.n(page.project.tests)) },
        { name: Skin.t("pulse.agents.tokens"), figure: Skin.n(page.project.outputTokens || 0) }
      ] : []
      delegate: MiniRow {
        required property var modelData
        tone: Skin.accent
        name: modelData.name
        figure: modelData.figure
      }
    }

    SectionTitle {
      visible: !!page.project && page.project.sessions.length > 0
      text: Skin.t("pulse.agents.sessions")
    }
    Repeater {
      model: page.project ? page.project.sessions.slice(0, 4) : []
      delegate: ListRow {
        required property var modelData
        tone: modelData.state === "idle" ? Skin.dim : page.stateColor(modelData.state)
        name: modelData.title || Skin.t("pulse.agents.untitled")
        detail: page.clock(modelData.start) + "–" + page.clock(modelData.end)
          + (modelData.branch && modelData.branch !== "HEAD" ? "  ·  " + modelData.branch : "")
          + "  ·  " + Skin.t("pulse.agents.sessionWorking").arg(page.durText(modelData.working))
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

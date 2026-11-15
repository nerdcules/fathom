import QtQuick
import QtQuick.Layouts
import "Format.js" as F

// The Command Deck's content: a clock, a summary line and four cards
// (System, Containers, .NET, AI) on a translucent scrim. Plain QtQuick only,
// so it can be rendered outside the shell for testing; Panel.qml supplies
// the data, theme, strings and number formatting.
Item {
  id: deck

  // Status JSON from `fathom-deck status`, or null before the first reading.
  property var info: null
  property string error: ""
  // Container names with an action in flight.
  property var busy: ({})
  property bool shown: true

  property color fg: "#e6f0ff"
  property color bg: "#0a1020"
  property color accent: "#4cc9f0"
  property color urgent: "#ff6b81"
  property color ok: "#3ddc97"
  property color warn: "#ffb547"
  property string fontFamily: "monospace"
  property real motion: 1
  property var locale: Qt.locale()
  // Translations: an object with t(key) and tn(key, count).
  property var strings: null
  // Number formatting: fmt(value, decimals) -> string.
  property var fmt: function(v, d) { return Number(v).toFixed(d || 0) }

  signal closeRequested()
  signal containerAction(string action, string name)
  signal logsRequested(string name)
  signal dockerRequested()

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property real u: Math.max(0.7, Math.min(1.25, Math.min(width / 1600, height / 1000)))

  readonly property var sys: info ? info.system : null
  readonly property var dock: info ? info.docker : null
  readonly property var net: info ? info.dotnet : null
  readonly property var ai: info ? info.ai : null
  readonly property var containers: dock && Array.isArray(dock.containers) ? dock.containers : []
  readonly property var dotnetApps: net ? F.byKind(net.processes, "app") : []
  readonly property var dotnetTooling: net ? F.byKind(net.processes, "tooling") : []
  readonly property var agents: ai && Array.isArray(ai.agents) ? ai.agents : []
  readonly property var mainDisk: sys && sys.disks && sys.disks.length > 0 ? sys.disks[0] : null

  function t(key) { return strings ? strings.t(key) : key }
  function tn(key, n) { return strings ? strings.tn(key, n) : key }
  function n(v, d) { return fmt(v, d || 0) }
  function size(v) { return F.bytes(v, fmt) }
  function levelColor(l) { return l === "bad" ? urgent : (l === "warn" ? warn : (l === "ok" ? ok : dim)) }

  function agentsWorking() {
    var c = 0
    for (var i = 0; i < agents.length; i++) if (F.agentBusy(agents[i])) c++
    return c
  }

  focus: true
  Keys.onEscapePressed: deck.closeRequested()

  // ---------------------------------------------------------------- parts

  component Label: Text {
    textFormat: Text.PlainText
    color: deck.fg
    font.family: deck.fontFamily
    font.pixelSize: 14 * deck.u
    elide: Text.ElideRight
  }

  component Dot: Rectangle {
    property color tone: deck.ok
    width: 8 * deck.u
    height: width
    radius: width / 2
    color: tone
  }

  component Meter: ColumnLayout {
    id: meter
    property string label: ""
    property string value: ""
    property real pct: 0
    property string tone: F.level(pct)
    spacing: 6 * deck.u
    Layout.fillWidth: true

    RowLayout {
      Layout.fillWidth: true
      Label {
        text: meter.label
        color: deck.dim
        font.pixelSize: 12 * deck.u
        font.letterSpacing: 1.2 * deck.u
        font.capitalization: Font.AllUppercase
      }
      Item { Layout.fillWidth: true }
      Label { text: meter.value; font.pixelSize: 13 * deck.u }
    }
    Rectangle {
      Layout.fillWidth: true
      height: 6 * deck.u
      radius: height / 2
      color: deck.faint
      Rectangle {
        width: parent.width * Math.max(0.01, Math.min(1, meter.pct / 100))
        height: parent.height
        radius: parent.radius
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: meter.tone === "ok" ? deck.accent : deck.levelColor(meter.tone) }
          GradientStop { position: 1; color: meter.tone === "ok" ? Qt.tint(deck.accent, "#809d8cff") : deck.levelColor(meter.tone) }
        }
        Behavior on width { NumberAnimation { duration: 300 * deck.motion; easing.type: Easing.OutCubic } }
      }
    }
  }

  component SectionTitle: Label {
    color: deck.dim
    font.pixelSize: 11 * deck.u
    font.letterSpacing: 1.4 * deck.u
    font.capitalization: Font.AllUppercase
    Layout.fillWidth: true
    Layout.topMargin: 4 * deck.u
  }

  component Empty: Label {
    color: deck.dim
    wrapMode: Text.WordWrap
    elide: Text.ElideNone
    Layout.fillWidth: true
  }

  component Pill: Rectangle {
    id: pill
    property string text: ""
    property string glyph: ""
    property string tip: ""
    property bool enabledAction: true
    signal clicked()
    implicitWidth: pillRow.implicitWidth + 20 * deck.u
    implicitHeight: 30 * deck.u
    radius: height / 2
    activeFocusOnTab: enabledAction
    color: !enabledAction ? "transparent" : (pillMouse.pressed ? Qt.rgba(deck.accent.r, deck.accent.g, deck.accent.b, 0.30)
          : (pillMouse.containsMouse || activeFocus ? Qt.rgba(deck.accent.r, deck.accent.g, deck.accent.b, 0.18) : deck.faint))
    border.width: activeFocus ? 1 : 0
    border.color: deck.accent
    opacity: enabledAction ? 1 : 0.4
    Accessible.role: Accessible.Button
    Accessible.name: tip || text
    Keys.onReturnPressed: if (enabledAction) clicked()
    Keys.onEnterPressed: if (enabledAction) clicked()
    Keys.onSpacePressed: if (enabledAction) clicked()

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 6 * deck.u
      Label {
        visible: pill.glyph !== ""
        text: pill.glyph
        color: deck.accent
        font.pixelSize: 13 * deck.u
        anchors.verticalCenter: parent.verticalCenter
      }
      Label {
        visible: pill.text !== ""
        text: pill.text
        font.pixelSize: 13 * deck.u
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: pill.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (pill.enabledAction) pill.clicked()
    }
    Tip { target: pill; text: pill.tip; show: pillMouse.containsMouse && pill.tip !== "" }
  }

  component Tip: Rectangle {
    id: tip
    property Item target: null
    property string text: ""
    property bool show: false
    parent: deck
    z: 100
    visible: opacity > 0
    opacity: show ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 * deck.motion } }
    width: tipText.implicitWidth + 16 * deck.u
    height: tipText.implicitHeight + 10 * deck.u
    radius: 6 * deck.u
    color: Qt.rgba(deck.bg.r, deck.bg.g, deck.bg.b, 0.96)
    border.width: 1
    border.color: deck.faint
    x: {
      if (!target || !show) return 0
      var p = target.mapToItem(deck, target.width / 2, 0)
      return Math.max(8, Math.min(deck.width - width - 8, p.x - width / 2))
    }
    y: {
      if (!target || !show) return 0
      return target.mapToItem(deck, 0, 0).y - height - 6 * deck.u
    }
    Label { id: tipText; anchors.centerIn: parent; text: tip.text; font.pixelSize: 12 * deck.u }
  }

  component Card: Rectangle {
    id: card
    property string title: ""
    property string subtitle: ""
    property string glyph: ""
    default property alias content: body.data
    property alias footer: footerSlot.data
    radius: 18 * deck.u
    color: Qt.rgba(deck.bg.r, deck.bg.g, deck.bg.b, 0.62)
    border.width: 1
    border.color: Qt.rgba(deck.accent.r, deck.accent.g, deck.accent.b, 0.22)

    // Swallow clicks so only the scrim around the cards closes the deck.
    MouseArea { anchors.fill: parent }

    // A faint top glow, like light catching glass.
    Rectangle {
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
      height: 60 * deck.u
      radius: card.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(deck.accent.r, deck.accent.g, deck.accent.b, 0.07) }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    implicitHeight: inner.implicitHeight + 44 * deck.u

    ColumnLayout {
      id: inner
      anchors.fill: parent
      anchors.margins: 22 * deck.u
      spacing: 14 * deck.u

      RowLayout {
        Layout.fillWidth: true
        spacing: 10 * deck.u
        Label {
          text: card.glyph
          color: deck.accent
          font.pixelSize: 18 * deck.u
          visible: card.glyph !== ""
        }
        Label {
          text: card.title
          font.pixelSize: 18 * deck.u
          font.weight: Font.DemiBold
        }
        Item { Layout.fillWidth: true }
        Label {
          text: card.subtitle
          color: deck.dim
          font.pixelSize: 12 * deck.u
          horizontalAlignment: Text.AlignRight
          Layout.maximumWidth: card.width * 0.5
        }
      }

      Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: body.implicitHeight
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ColumnLayout {
          id: body
          width: flick.width
          spacing: 12 * deck.u
        }
      }

      RowLayout {
        id: footerSlot
        Layout.fillWidth: true
        spacing: 8 * deck.u
        visible: children.length > 0
      }
    }
  }

  // A card in the grid, sharing the row's width equally.
  component CardCell: Card {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 1
    Layout.minimumHeight: 240 * deck.u
  }

  // A row in a list: a dot, a name with a detail line, and figures on the right.
  component Row2: Item {
    id: row
    property color tone: deck.ok
    property bool showDot: true
    property string name: ""
    property string detail: ""
    property string right1: ""
    property string right2: ""
    readonly property bool hovered: rowHover.hovered
    default property alias actions: actionsRow.data
    Layout.fillWidth: true
    implicitHeight: 40 * deck.u

    Rectangle {
      anchors.fill: parent
      anchors.margins: -4 * deck.u
      radius: 10 * deck.u
      color: rowHover.hovered || actionsRow.activeFocusInside ? deck.faint : "transparent"
    }
    HoverHandler { id: rowHover }

    Dot {
      id: rowDot
      visible: row.showDot
      tone: row.tone
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      anchors.left: row.showDot ? rowDot.right : parent.left
      anchors.leftMargin: row.showDot ? 10 * deck.u : 0
      anchors.right: rightSide.left
      anchors.rightMargin: 8 * deck.u
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2 * deck.u
      Label { width: parent.width; text: row.name }
      Label { width: parent.width; text: row.detail; visible: text !== ""; color: deck.dim; font.pixelSize: 12 * deck.u }
    }
    Item {
      id: rightSide
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(figures.implicitWidth, actionsRow.implicitWidth)
      height: parent.height
      Column {
        id: figures
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !actionsRow.showing
        Label { anchors.right: parent.right; text: row.right1; font.pixelSize: 13 * deck.u }
        Label { anchors.right: parent.right; text: row.right2; visible: text !== ""; color: deck.dim; font.pixelSize: 12 * deck.u }
      }
      Row {
        id: actionsRow
        property bool activeFocusInside: {
          for (var i = 0; i < children.length; i++) if (children[i].activeFocus) return true
          return false
        }
        readonly property bool showing: children.length > 0 && (rowHover.hovered || activeFocusInside)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4 * deck.u
        opacity: showing ? 1 : 0
        // Hidden until hover, but still reachable with Tab: focusing one
        // shows them all.
      }
    }
  }

  // ---------------------------------------------------------------- scene

  // The scrim. Hyprland blurs what's behind it (see fathom-deck.lua).
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(deck.bg.r * 0.5, deck.bg.g * 0.5, deck.bg.b * 0.5, 0.62)
    MouseArea { anchors.fill: parent; onClicked: deck.closeRequested() }
  }

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: 48 * deck.u
    opacity: deck.shown ? 1 : 0
    scale: deck.shown ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: 180 * deck.motion; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 180 * deck.motion; easing.type: Easing.OutCubic } }

    readonly property real contentWidth: Math.min(width, 1680 * deck.u)
    readonly property int columns: contentWidth >= 1100 * deck.u ? 4 : 2

    ColumnLayout {
      id: column
      width: stage.contentWidth
      anchors.horizontalCenter: parent.horizontalCenter
      height: parent.height
      spacing: 28 * deck.u

      // Clock and summary.
      RowLayout {
        Layout.fillWidth: true
        spacing: 32 * deck.u

        ColumnLayout {
          spacing: 0
          Label {
            id: clockText
            text: clock.now.toLocaleTimeString(deck.locale, "HH:mm")
            font.pixelSize: 84 * deck.u
            font.weight: Font.Light
            font.letterSpacing: -2 * deck.u
          }
          Label {
            text: clock.now.toLocaleDateString(deck.locale, "dddd d MMMM")
            color: deck.dim
            font.pixelSize: 18 * deck.u
          }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
          Layout.alignment: Qt.AlignBottom
          spacing: 8 * deck.u
          Repeater {
            model: deck.summary()
            delegate: RowLayout {
              required property var modelData
              spacing: 10 * deck.u
              Layout.alignment: Qt.AlignRight
              Dot { tone: deck.levelColor(modelData.tone) }
              Label { text: modelData.text; font.pixelSize: 15 * deck.u }
            }
          }
        }
      }

      // The cards.
      GridLayout {
        id: grid
        Layout.fillWidth: true
        // As tall as the tallest card needs, shrinking (and scrolling) when
        // the screen is shorter.
        // (Nested layouts fill by default, hence the explicit false.)
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        columns: stage.columns
        columnSpacing: 20 * deck.u
        rowSpacing: 20 * deck.u

        // ------------------------------------------------ System
        CardCell {
          title: deck.t("system.title")
          glyph: ""
          subtitle: deck.sys ? deck.uptimeText(deck.sys.uptime) : ""

          Meter {
            label: deck.t("system.cpu")
            pct: deck.sys && deck.sys.cpu !== null ? deck.sys.cpu : 0
            value: deck.sys && deck.sys.cpu !== null ? deck.n(deck.sys.cpu) + "%" : "–"
            tone: "ok"
          }
          Meter {
            visible: !!deck.sys && deck.sys.gpu !== null && deck.sys.gpu !== undefined
            label: deck.t("system.gpu")
            pct: deck.sys && deck.sys.gpu !== null ? deck.sys.gpu : 0
            value: deck.sys && deck.sys.gpu !== null ? deck.n(deck.sys.gpu) + "%" : "–"
            tone: "ok"
          }
          Meter {
            label: deck.t("system.memory")
            pct: deck.sys ? F.percent(deck.sys.memUsed, deck.sys.memTotal) : 0
            value: deck.sys ? deck.t("system.ofTotal").arg(deck.size(deck.sys.memUsed)).arg(deck.size(deck.sys.memTotal)) : "–"
            tone: F.level(pct)
          }
          Repeater {
            model: deck.sys ? deck.sys.disks : []
            delegate: ColumnLayout {
              required property var modelData
              readonly property real pct: F.percent(modelData.used, modelData.size)
              Layout.fillWidth: true
              spacing: 4 * deck.u
              Meter {
                label: deck.t("system.disk").arg(modelData.mount)
                pct: parent.pct
                value: deck.t("system.free").arg(deck.size(modelData.free))
              }
              Label {
                visible: F.level(parent.pct) !== "ok"
                text: F.level(parent.pct) === "bad" ? deck.t("system.diskFull") : deck.t("system.diskFilling")
                color: deck.levelColor(F.level(parent.pct))
                font.pixelSize: 12 * deck.u
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }
            }
          }

          SectionTitle {
            visible: deck.dock && deck.dock.state === "ok" && deck.dock.disk && deck.dock.disk.length > 0
            text: deck.t("system.dockerSpace")
          }
          Label {
            readonly property var space: deck.dock ? F.dockerSpace(deck.dock.disk) : null
            visible: !!space && space.images !== ""
            text: space ? deck.t("system.dockerSpaceLine").arg(space.images).arg(space.cache || "0B").arg(space.volumes || "0B") : ""
            color: deck.dim
            font.pixelSize: 12 * deck.u
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            Layout.fillWidth: true
          }
        }

        // ------------------------------------------------ Containers
        CardCell {
          title: deck.t("docker.title")
          glyph: ""
          subtitle: deck.dock && deck.dock.state === "ok" && deck.containers.length > 0
            ? deck.t("docker.running").arg(deck.n(F.countRunning(deck.containers))).arg(deck.n(deck.containers.length)) : ""

          Empty {
            visible: !deck.dock || deck.dock.state !== "ok" || deck.containers.length === 0
            text: !deck.info ? deck.t("loading")
              : (deck.dock.state === "missing" ? deck.t("docker.missing")
              : (deck.dock.state === "down" ? deck.t("docker.down") : deck.t("docker.none")))
          }

          Repeater {
            model: deck.dock && deck.dock.state === "ok" ? F.groupContainers(deck.containers) : []
            delegate: ColumnLayout {
              id: group
              required property var modelData
              Layout.fillWidth: true
              spacing: 8 * deck.u
              SectionTitle { text: group.modelData.project !== "" ? group.modelData.project : deck.t("docker.standalone") }
              Repeater {
                model: group.modelData.containers
                delegate: Row2 {
                  id: crow
                  required property var modelData
                  readonly property string health: F.containerHealth(modelData)
                  readonly property bool running: modelData.state === "running"
                  readonly property bool working: deck.busy[modelData.name] === true
                  readonly property bool actionable: F.validContainerName(modelData.name) && !working
                  tone: deck.levelColor(health)
                  name: modelData.name
                  detail: working ? deck.t("docker.working") : (F.hostPorts(modelData.ports) || modelData.status)
                  right1: running && modelData.cpu !== "" ? modelData.cpu : ""
                  right2: running ? String(modelData.mem).split(" / ")[0]
                    : (modelData.state === "restarting" ? deck.t("docker.restarting") : deck.t("docker.stopped"))

                  Pill {
                    glyph: crow.running ? "" : ""
                    tip: crow.running ? deck.t("docker.stop") : deck.t("docker.start")
                    enabledAction: crow.actionable
                    onClicked: deck.containerAction(crow.running ? "stop" : "start", crow.modelData.name)
                  }
                  Pill {
                    glyph: ""
                    tip: deck.t("docker.restart")
                    enabledAction: crow.actionable && crow.running
                    onClicked: deck.containerAction("restart", crow.modelData.name)
                  }
                  Pill {
                    glyph: ""
                    tip: deck.t("docker.logs")
                    enabledAction: F.validContainerName(crow.modelData.name)
                    onClicked: deck.logsRequested(crow.modelData.name)
                  }
                }
              }
            }
          }

          footer: [
            Pill {
              visible: !!deck.dock && deck.dock.state === "ok"
              glyph: ""
              text: deck.t("docker.lazydocker")
              onClicked: deck.dockerRequested()
            }
          ]
        }

        // ------------------------------------------------ .NET
        CardCell {
          title: ".NET"
          glyph: ""
          subtitle: deck.net && deck.net.sdks.length > 0
            ? deck.t("dotnet.sdk").arg(deck.net.sdks[deck.net.sdks.length - 1]) : (deck.info ? deck.t("dotnet.noSdk") : "")

          SectionTitle { text: deck.t("dotnet.running") }
          Empty {
            visible: deck.dotnetApps.length === 0
            text: deck.info ? deck.t("dotnet.none") : deck.t("loading")
          }
          Repeater {
            model: deck.dotnetApps
            delegate: Row2 {
              required property var modelData
              tone: deck.ok
              name: modelData.name
              detail: modelData.folder
              right1: deck.n(modelData.cpu, modelData.cpu < 10 ? 1 : 0) + "%"
              right2: deck.size(modelData.rss)
            }
          }

          SectionTitle {
            visible: deck.dotnetTooling.length > 0
            text: deck.t("dotnet.tooling")
          }
          Label {
            visible: deck.dotnetTooling.length > 0
            text: deck.tn("dotnet.toolingLine", deck.dotnetTooling.length)
              .arg(deck.n(deck.dotnetTooling.length)).arg(deck.size(F.sum(deck.dotnetTooling, "rss")))
            color: deck.dim
            font.pixelSize: 12 * deck.u
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            Layout.fillWidth: true
          }
        }

        // ------------------------------------------------ AI
        CardCell {
          title: deck.t("ai.title")
          glyph: ""
          subtitle: deck.agents.length > 0 ? deck.tn("ai.working", deck.agentsWorking()).arg(deck.n(deck.agentsWorking())) : ""

          SectionTitle { text: deck.t("ai.agents") }
          Empty {
            visible: deck.agents.length === 0
            text: deck.info ? deck.t("ai.noAgents") : deck.t("loading")
          }
          Repeater {
            model: deck.agents
            delegate: Row2 {
              required property var modelData
              readonly property bool working: F.agentBusy(modelData)
              tone: working ? deck.accent : deck.dim
              name: modelData.name
              detail: deck.t(modelData.where === "editor" ? "ai.inEditor" : "ai.inTerminal").arg(modelData.folder)
              right1: working ? deck.t("ai.busy") : deck.t("ai.idle")
              right2: deck.size(modelData.rss)
            }
          }

          SectionTitle { text: "Ollama" }
          Empty {
            visible: !!deck.info && !deck.ai.ollama
            text: deck.t("ai.noOllama")
          }
          Repeater {
            model: deck.ai && deck.ai.ollama ? deck.ai.ollama.loaded : []
            delegate: Row2 {
              required property var modelData
              tone: deck.accent
              name: modelData.name
              detail: deck.t("ai.loaded")
              right1: deck.size(modelData.vram)
              right2: ""
            }
          }
          Label {
            visible: !!deck.ai && !!deck.ai.ollama
            text: deck.ai && deck.ai.ollama ? deck.tn("ai.models", deck.ai.ollama.models.length).arg(deck.n(deck.ai.ollama.models.length)) : ""
            color: deck.dim
            font.pixelSize: 12 * deck.u
          }
        }
      }

      Item { Layout.fillHeight: true }

      // Footer.
      RowLayout {
        Layout.fillWidth: true
        Label {
          text: deck.error !== "" ? deck.error : deck.t("hint")
          color: deck.error !== "" ? deck.urgent : deck.dim
          font.pixelSize: 12 * deck.u
          Layout.fillWidth: true
        }
        Label {
          visible: !!deck.info
          text: deck.info ? deck.t("updated").arg(new Date(deck.info.time * 1000).toLocaleTimeString(deck.locale, "HH:mm:ss")) : ""
          color: deck.dim
          font.pixelSize: 12 * deck.u
        }
      }
    }
  }

  QtObject {
    id: clock
    property date now: new Date()
  }
  Timer {
    interval: 1000
    running: deck.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: clock.now = new Date()
  }

  function uptimeText(seconds) {
    var up = F.uptime(seconds)
    if (up.days > 0) return tn("system.upDays", up.days).arg(n(up.days)).arg(n(up.hours))
    if (up.hours > 0) return t("system.upHours").arg(n(up.hours)).arg(n(up.minutes))
    return t("system.upMinutes").arg(n(up.minutes))
  }

  // The lines beside the clock: what needs attention first, then the rest.
  function summary() {
    var out = []
    if (!info) return [{ tone: "stopped", text: t("loading") }]
    if (dock && dock.state === "ok" && containers.length > 0) {
      var bad = 0
      for (var i = 0; i < containers.length; i++) if (F.containerHealth(containers[i]) === "bad") bad++
      out.push({
        tone: bad > 0 ? "bad" : "ok",
        text: bad > 0 ? tn("summary.containersBad", bad).arg(n(bad))
          : t("summary.containers").arg(n(F.countRunning(containers))).arg(n(containers.length))
      })
    } else if (dock && dock.state === "down") {
      out.push({ tone: "stopped", text: t("docker.down") })
    }
    if (dotnetApps.length > 0) out.push({ tone: "ok", text: tn("summary.dotnet", dotnetApps.length).arg(n(dotnetApps.length)) })
    if (agents.length > 0) {
      var w = agentsWorking()
      out.push({ tone: w > 0 ? "ok" : "stopped", text: tn("summary.agents", agents.length).arg(n(agents.length)).arg(n(w)) })
    }
    if (mainDisk) {
      var p = F.percent(mainDisk.used, mainDisk.size)
      out.push({ tone: F.level(p), text: t("summary.disk").arg(n(p)) })
    }
    return out
  }
}

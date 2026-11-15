import QtQuick
import QtQuick.Layouts
import "."
import "Format.js" as F

// The Deck page: System, Containers, .NET and AI cards, from
// `fathom-deck status`.
GridLayout {
  id: page

  property var info: null
  // Container names with an action in flight.
  property var busy: ({})
  property int columnCount: 4

  signal containerAction(string action, string name)
  signal logsRequested(string name)
  signal dockerRequested()

  readonly property var sys: info ? info.system : null
  readonly property var dock: info ? info.docker : null
  readonly property var net: info ? info.dotnet : null
  readonly property var ai: info ? info.ai : null
  readonly property var containers: dock && Array.isArray(dock.containers) ? dock.containers : []
  readonly property var dotnetApps: net ? F.byKind(net.processes, "app") : []
  readonly property var dotnetTooling: net ? F.byKind(net.processes, "tooling") : []
  readonly property var agents: ai && Array.isArray(ai.agents) ? ai.agents : []
  readonly property var mainDisk: sys && sys.disks && sys.disks.length > 0 ? sys.disks[0] : null

  columns: columnCount
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  function agentsWorking() {
    var c = 0
    for (var i = 0; i < agents.length; i++) if (F.agentBusy(agents[i])) c++
    return c
  }

  function uptimeText(seconds) {
    var up = F.uptime(seconds)
    if (up.days > 0) return Skin.tn("system.upDays", up.days).arg(Skin.n(up.days)).arg(Skin.n(up.hours))
    if (up.hours > 0) return Skin.t("system.upHours").arg(Skin.n(up.hours)).arg(Skin.n(up.minutes))
    return Skin.t("system.upMinutes").arg(Skin.n(up.minutes))
  }

  // The lines beside the clock: what needs attention first, then the rest.
  function summary() {
    var out = []
    if (!info) return [{ tone: "stopped", text: Skin.t("loading") }]
    if (dock && dock.state === "ok" && containers.length > 0) {
      var bad = 0
      for (var i = 0; i < containers.length; i++) if (F.containerHealth(containers[i]) === "bad") bad++
      out.push({
        tone: bad > 0 ? "bad" : "ok",
        text: bad > 0 ? Skin.tn("summary.containersBad", bad).arg(Skin.n(bad))
          : Skin.t("summary.containers").arg(Skin.n(F.countRunning(containers))).arg(Skin.n(containers.length))
      })
    } else if (dock && dock.state === "down") {
      out.push({ tone: "stopped", text: Skin.t("docker.down") })
    }
    if (dotnetApps.length > 0) out.push({ tone: "ok", text: Skin.tn("summary.dotnet", dotnetApps.length).arg(Skin.n(dotnetApps.length)) })
    if (agents.length > 0) {
      var w = agentsWorking()
      out.push({ tone: w > 0 ? "ok" : "stopped", text: Skin.tn("summary.agents", agents.length).arg(Skin.n(agents.length)).arg(Skin.n(w)) })
    }
    var mail = info.mail && Array.isArray(info.mail.accounts) ? info.mail.accounts : []
    if (mail.length > 0) {
      var unread = 0
      var signedOut = false
      for (var m = 0; m < mail.length; m++) {
        if (typeof mail[m].unread === "number") unread += mail[m].unread
        if (mail[m].signedIn === false) signedOut = true
      }
      if (signedOut) out.push({ tone: "warn", text: Skin.t("summary.mailSignIn") })
      else out.push({ tone: unread > 0 ? "ok" : "stopped", text: Skin.tn("summary.mail", unread).arg(Skin.n(unread)) })
    }
    if (mainDisk) {
      var p = F.percent(mainDisk.used, mainDisk.size)
      out.push({ tone: F.level(p), text: Skin.t("summary.disk").arg(Skin.n(p)) })
    }
    return out
  }

  // ------------------------------------------------ System
  Card {
    title: Skin.t("system.title")
    glyph: ""
    subtitle: page.sys ? page.uptimeText(page.sys.uptime) : ""

    Meter {
      label: Skin.t("system.cpu")
      pct: page.sys && page.sys.cpu !== null ? page.sys.cpu : 0
      value: page.sys && page.sys.cpu !== null ? Skin.n(page.sys.cpu) + "%" : "–"
      tone: "ok"
    }
    Meter {
      visible: !!page.sys && page.sys.gpu !== null && page.sys.gpu !== undefined
      label: Skin.t("system.gpu")
      pct: page.sys && page.sys.gpu !== null ? page.sys.gpu : 0
      value: page.sys && page.sys.gpu !== null ? Skin.n(page.sys.gpu) + "%" : "–"
      tone: "ok"
    }
    Meter {
      label: Skin.t("system.memory")
      pct: page.sys ? F.percent(page.sys.memUsed, page.sys.memTotal) : 0
      value: page.sys ? Skin.t("system.ofTotal").arg(Skin.size(page.sys.memUsed)).arg(Skin.size(page.sys.memTotal)) : "–"
    }
    Repeater {
      model: page.sys ? page.sys.disks : []
      delegate: ColumnLayout {
        id: diskRow
        required property var modelData
        readonly property real pct: F.percent(modelData.used, modelData.size)
        Layout.fillWidth: true
        spacing: 4 * Skin.u
        Meter {
          label: Skin.t("system.disk").arg(diskRow.modelData.mount)
          pct: diskRow.pct
          value: Skin.t("system.free").arg(Skin.size(diskRow.modelData.free))
        }
        Label {
          visible: F.level(diskRow.pct) !== "ok"
          text: F.level(diskRow.pct) === "bad" ? Skin.t("system.diskFull") : Skin.t("system.diskFilling")
          color: Skin.levelColor(F.level(diskRow.pct))
          font.pixelSize: 12 * Skin.u
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          Layout.fillWidth: true
        }
      }
    }

    SectionTitle {
      visible: !!page.dock && page.dock.state === "ok" && !!page.dock.disk && page.dock.disk.length > 0
      text: Skin.t("system.dockerSpace")
    }
    Label {
      readonly property var space: page.dock ? F.dockerSpace(page.dock.disk) : null
      visible: !!space && space.images !== ""
      text: space ? Skin.t("system.dockerSpaceLine").arg(space.images).arg(space.cache || "0B").arg(space.volumes || "0B") : ""
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }
  }

  // ------------------------------------------------ Containers
  Card {
    title: Skin.t("docker.title")
    glyph: ""
    subtitle: page.dock && page.dock.state === "ok" && page.containers.length > 0
      ? Skin.t("docker.running").arg(Skin.n(F.countRunning(page.containers))).arg(Skin.n(page.containers.length)) : ""

    Empty {
      visible: !page.dock || page.dock.state !== "ok" || page.containers.length === 0
      text: !page.info ? Skin.t("loading")
        : (page.dock.state === "missing" ? Skin.t("docker.missing")
        : (page.dock.state === "down" ? Skin.t("docker.down") : Skin.t("docker.none")))
    }

    Repeater {
      model: page.dock && page.dock.state === "ok" ? F.groupContainers(page.containers) : []
      delegate: ColumnLayout {
        id: group
        required property var modelData
        Layout.fillWidth: true
        spacing: 8 * Skin.u
        SectionTitle { text: group.modelData.project !== "" ? group.modelData.project : Skin.t("docker.standalone") }
        Repeater {
          model: group.modelData.containers
          delegate: ListRow {
            id: crow
            required property var modelData
            readonly property string health: F.containerHealth(modelData)
            readonly property bool running: modelData.state === "running"
            readonly property bool working: page.busy[modelData.name] === true
            readonly property bool actionable: F.validContainerName(modelData.name) && !working
            tone: Skin.levelColor(health)
            name: modelData.name
            detail: working ? Skin.t("docker.working") : (F.hostPorts(modelData.ports) || modelData.status)
            right1: running && modelData.cpu !== "" ? modelData.cpu : ""
            right2: running ? String(modelData.mem).split(" / ")[0]
              : (modelData.state === "restarting" ? Skin.t("docker.restarting") : Skin.t("docker.stopped"))

            Pill {
              glyph: crow.running ? "" : ""
              tip: crow.running ? Skin.t("docker.stop") : Skin.t("docker.start")
              enabledAction: crow.actionable
              onClicked: page.containerAction(crow.running ? "stop" : "start", crow.modelData.name)
            }
            Pill {
              glyph: ""
              tip: Skin.t("docker.restart")
              enabledAction: crow.actionable && crow.running
              onClicked: page.containerAction("restart", crow.modelData.name)
            }
            Pill {
              glyph: ""
              tip: Skin.t("docker.logs")
              enabledAction: F.validContainerName(crow.modelData.name)
              onClicked: page.logsRequested(crow.modelData.name)
            }
          }
        }
      }
    }

    footer: [
      Pill {
        visible: !!page.dock && page.dock.state === "ok"
        glyph: ""
        text: Skin.t("docker.lazydocker")
        onClicked: page.dockerRequested()
      }
    ]
  }

  // ------------------------------------------------ .NET
  Card {
    title: ".NET"
    glyph: ""
    subtitle: page.net && page.net.sdks.length > 0
      ? Skin.t("dotnet.sdk").arg(page.net.sdks[page.net.sdks.length - 1]) : (page.info ? Skin.t("dotnet.noSdk") : "")

    SectionTitle { text: Skin.t("dotnet.running") }
    Empty {
      visible: page.dotnetApps.length === 0
      text: page.info ? Skin.t("dotnet.none") : Skin.t("loading")
    }
    Repeater {
      model: page.dotnetApps
      delegate: ListRow {
        required property var modelData
        tone: Skin.ok
        name: modelData.name
        detail: modelData.folder
        right1: Skin.n(modelData.cpu, modelData.cpu < 10 ? 1 : 0) + "%"
        right2: Skin.size(modelData.rss)
      }
    }

    SectionTitle {
      visible: page.dotnetTooling.length > 0
      text: Skin.t("dotnet.tooling")
    }
    Label {
      visible: page.dotnetTooling.length > 0
      text: Skin.tn("dotnet.toolingLine", page.dotnetTooling.length)
        .arg(Skin.n(page.dotnetTooling.length)).arg(Skin.size(F.sum(page.dotnetTooling, "rss")))
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }
  }

  // ------------------------------------------------ AI
  Card {
    title: Skin.t("ai.title")
    glyph: ""
    subtitle: page.agents.length > 0 ? Skin.tn("ai.working", page.agentsWorking()).arg(Skin.n(page.agentsWorking())) : ""

    SectionTitle { text: Skin.t("ai.agents") }
    Empty {
      visible: page.agents.length === 0
      text: page.info ? Skin.t("ai.noAgents") : Skin.t("loading")
    }
    Repeater {
      model: page.agents
      delegate: ListRow {
        required property var modelData
        readonly property bool working: F.agentBusy(modelData)
        tone: working ? Skin.accent : Skin.dim
        name: modelData.name
        detail: Skin.t(modelData.where === "editor" ? "ai.inEditor" : "ai.inTerminal").arg(modelData.folder)
        right1: working ? Skin.t("ai.busy") : Skin.t("ai.idle")
        right2: Skin.size(modelData.rss)
      }
    }

    SectionTitle { text: "Ollama" }
    Empty {
      visible: !!page.info && !!page.ai && !page.ai.ollama
      text: Skin.t("ai.noOllama")
    }
    Repeater {
      model: page.ai && page.ai.ollama ? page.ai.ollama.loaded : []
      delegate: ListRow {
        required property var modelData
        tone: Skin.accent
        name: modelData.name
        detail: Skin.t("ai.loaded")
        right1: Skin.size(modelData.vram)
      }
    }
    Label {
      visible: !!page.ai && !!page.ai.ollama
      text: page.ai && page.ai.ollama ? Skin.tn("ai.models", page.ai.ollama.models.length).arg(Skin.n(page.ai.ollama.models.length)) : ""
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
    }
  }
}

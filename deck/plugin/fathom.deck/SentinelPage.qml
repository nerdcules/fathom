import QtQuick
import QtQuick.Layouts
import "."
import "Format.js" as F

// The Sentinel page: is this machine protected, what happened today, and
// who's on the network, from `fathom-sentinel status`.
GridLayout {
  id: page

  property var sentinel: null

  signal lockdownRequested(bool on)
  signal blockRequested(string ip)
  signal unblockRequested(string ip)
  signal trustRequested(string mac, bool trust)
  signal checkFilesRequested()
  signal logRequested(string what)
  signal snitchRequested()

  readonly property var fw: sentinel ? sentinel.firewall : null
  readonly property var snitch: sentinel ? sentinel.opensnitch : null
  readonly property var files: sentinel ? sentinel.integrity : null
  readonly property var net: sentinel ? sentinel.network : null
  readonly property var events: sentinel && Array.isArray(sentinel.events) ? sentinel.events : []
  readonly property var devices: net && Array.isArray(net.devices) ? net.devices : []
  readonly property var blocks: sentinel ? sentinel.blocksToday : null
  readonly property int attention: sentinel ? sentinel.attention || 0 : 0
  readonly property int newDevices: {
    var n = 0
    for (var i = 0; i < devices.length; i++) if (!devices[i].trusted) n++
    return n
  }

  // "bad" when unprotected, "warn" when something needs a look.
  readonly property string health: {
    if (!sentinel) return "stopped"
    if (!fw || !fw.on || !sentinel.watching) return "bad"
    if (attention > 0) return "warn"
    return "ok"
  }

  columns: 3
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  function agoText(then) {
    if (!sentinel || !then) return ""
    var a = F.ago(then, sentinel.time)
    return Skin.tn("care.ago." + a.unit, a.n).arg(Skin.n(a.n))
  }

  function clock(t) {
    return new Date(t * 1000).toLocaleTimeString(Skin.locale, "HH:mm")
  }

  function summary() {
    if (!sentinel) return [{ tone: "stopped", text: Skin.t("loading") }]
    var out = []
    if (health === "bad") out.push({ tone: "bad", text: !fw || !fw.on ? Skin.t("sentinel.fwOff") : Skin.t("sentinel.notWatching") })
    else if (attention > 0) out.push({ tone: "warn", text: Skin.tn("sentinel.summary.attention", attention).arg(Skin.n(attention)) })
    else out.push({ tone: "ok", text: Skin.t("sentinel.protected") })
    if (fw && fw.lockdown) out.push({ tone: "warn", text: Skin.t("sentinel.lockdownOn") })
    if (blocks) out.push({ tone: "ok", text: Skin.tn("sentinel.summary.blocked", blocks.total).arg(Skin.n(blocks.total)) })
    if (net && net.ssid) out.push({ tone: newDevices > 0 ? "warn" : "ok", text: Skin.tn("sentinel.summary.devices", devices.length).arg(Skin.n(devices.length)).arg(net.ssid) })
    return out
  }

  // ------------------------------------------------ Shield
  Card {
    title: Skin.t("sentinel.title")
    glyph: ""
    subtitle: page.health === "ok" ? Skin.t("sentinel.protected") : (page.health === "bad" ? Skin.t("sentinel.exposed") : Skin.t("sentinel.needsLook"))
    subtitleColor: Skin.levelColor(page.health)

    Empty {
      visible: !!page.sentinel && !page.sentinel.watching
      text: Skin.t("sentinel.notWatchingDetail")
      color: Skin.warn
    }

    ListRow {
      tone: page.fw && page.fw.on ? Skin.ok : Skin.urgent
      name: page.fw && page.fw.on ? Skin.t("sentinel.fwOnTitle") : Skin.t("sentinel.fwOff")
      detail: page.fw && page.fw.lockdown ? Skin.t("sentinel.lockdownDetail")
        : (page.blocks ? Skin.tn("sentinel.blockedToday", page.blocks.total).arg(Skin.n(page.blocks.total)) : "")
      detailColor: page.fw && page.fw.lockdown ? Skin.warn : Skin.dim
      alwaysShowActions: true
      Pill {
        visible: !!page.sentinel && page.sentinel.rootParts
        glyph: ""
        text: page.fw && page.fw.lockdown ? Skin.t("sentinel.endLockdown") : Skin.t("sentinel.lockdown")
        primary: !!page.fw && page.fw.lockdown
        tip: Skin.t("sentinel.lockdownTip")
        onClicked: page.lockdownRequested(!(page.fw && page.fw.lockdown))
      }
    }

    ListRow {
      tone: !page.snitch || !page.snitch.installed ? Skin.dim : (page.snitch.active ? Skin.ok : Skin.warn)
      name: !page.snitch || !page.snitch.installed ? Skin.t("sentinel.snitchMissing")
        : (page.snitch.active ? Skin.t("sentinel.snitchOn") : Skin.t("sentinel.snitchOff"))
      detail: page.snitch && page.snitch.installed
        ? Skin.tn("sentinel.snitchRules", page.snitch.rules).arg(Skin.n(page.snitch.rules)).arg(Skin.n(page.snitch.allow)).arg(Skin.n(page.snitch.deny))
        : Skin.t("sentinel.snitchMissingDetail")
      alwaysShowActions: true
      Pill {
        visible: !!page.snitch && page.snitch.installed
        glyph: ""
        tip: Skin.t("sentinel.openSnitch")
        onClicked: page.snitchRequested()
      }
    }

    ListRow {
      // Differences the first check found are usually settings; only new
      // ones are flagged, in Today.
      tone: !page.files ? Skin.dim : (page.files.altered > 0 ? Skin.dim : Skin.ok)
      name: !page.files ? Skin.t("sentinel.filesPending")
        : (page.files.altered > 0 ? Skin.tn("sentinel.filesDiffer", page.files.altered).arg(Skin.n(page.files.altered)) : Skin.t("sentinel.filesMatch"))
      detail: page.files ? Skin.t("sentinel.filesDetail").arg(Skin.n(page.files.files)).arg(page.agoText(page.files.checkedAt))
        : (page.sentinel && page.sentinel.rootParts ? Skin.t("sentinel.filesFirst") : Skin.t("sentinel.filesNotInstalled"))
      alwaysShowActions: true
      Pill {
        visible: !!page.sentinel && page.sentinel.rootParts
        glyph: ""
        tip: Skin.t("sentinel.checkFiles")
        onClicked: page.checkFilesRequested()
      }
      Pill {
        visible: !!page.files
        glyph: ""
        tip: Skin.t("sentinel.showLog")
        onClicked: page.logRequested("files")
      }
    }

    // Beside the firewall it belongs to. In Today, under the events, it was
    // out of view on a 1000 px tall screen.
    SectionTitle {
      visible: !!page.blocks && page.blocks.top.length > 0
      text: Skin.t("sentinel.blockedFrom")
      Layout.topMargin: 6 * Skin.u
    }
    Repeater {
      model: page.blocks ? page.blocks.top : []
      delegate: ListRow {
        id: brow
        required property var modelData
        tone: modelData.public ? Skin.warn : Skin.dim
        name: modelData.src
        detail: modelData.public ? Skin.t("sentinel.fromInternet") : Skin.t("sentinel.fromNetwork")
        right1: Skin.tn("sentinel.times", modelData.count).arg(Skin.n(modelData.count))
        Pill {
          visible: !!page.sentinel && page.sentinel.rootParts
          text: Skin.t("sentinel.block")
          onClicked: page.blockRequested(brow.modelData.src)
        }
        Pill {
          glyph: ""
          tip: Skin.t("sentinel.showLog")
          onClicked: page.logRequested("firewall")
        }
      }
    }

    SectionTitle { text: Skin.t("sentinel.watchingTitle"); Layout.topMargin: 6 * Skin.u }
    Label {
      text: Skin.t("sentinel.watchingList") + (page.snitch && page.snitch.installed ? ", OpenSnitch" : "")
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }
  }

  // ------------------------------------------------ Today
  Card {
    Layout.preferredWidth: 1.25
    title: Skin.t("sentinel.today")
    glyph: ""
    subtitle: page.attention > 0 ? Skin.tn("care.needYou", page.attention).arg(Skin.n(page.attention)) : ""
    subtitleColor: Skin.warn

    Empty {
      visible: !!page.sentinel && page.events.length === 0
      text: Skin.t("sentinel.quiet")
    }
    Repeater {
      model: page.events.slice(0, 14)
      delegate: ListRow {
        id: erow
        required property var modelData
        readonly property var d: modelData.data || ({})
        tone: Skin.levelColor(modelData.level === "info" ? "ok" : modelData.level)
        name: page.clock(modelData.time) + "  " + modelData.title
        detail: modelData.detail
        Pill {
          visible: erow.modelData.kind === "device" && !!erow.d.mac
          text: Skin.t("sentinel.trust")
          onClicked: page.trustRequested(erow.d.mac, true)
        }
        Pill {
          visible: !!(erow.d.src || erow.d.ip) && !!page.sentinel && page.sentinel.rootParts
          text: Skin.t("sentinel.block")
          onClicked: page.blockRequested(erow.d.src || erow.d.ip)
        }
        Pill {
          visible: erow.modelData.kind === "auth" || erow.modelData.kind === "scan" || erow.modelData.kind === "files"
          glyph: ""
          tip: Skin.t("sentinel.showLog")
          onClicked: page.logRequested(erow.modelData.kind === "files" ? "files" : (erow.modelData.kind === "scan" ? "firewall" : "signins"))
        }
      }
    }
  }

  // ------------------------------------------------ Network
  Card {
    title: page.net && page.net.ssid ? page.net.ssid : Skin.t("sentinel.network")
    glyph: ""
    subtitle: page.devices.length > 0 ? Skin.tn("sentinel.devices", page.devices.length).arg(Skin.n(page.devices.length)) : ""

    Empty {
      visible: !!page.sentinel && page.devices.length === 0
      text: Skin.t("sentinel.noDevices")
    }
    Repeater {
      model: page.devices
      delegate: ListRow {
        id: drow
        required property var modelData
        tone: modelData.trusted ? Skin.ok : Skin.warn
        name: modelData.ip + (modelData.gateway ? "  ·  " + Skin.t("sentinel.router") : "")
        detail: (modelData.vendor || Skin.t("sentinel.unknownMaker")) + (modelData.trusted ? "" : " · " + Skin.t("sentinel.new"))
        right1: page.agoText(modelData.last)
        Pill {
          text: drow.modelData.trusted ? Skin.t("sentinel.forget") : Skin.t("sentinel.trust")
          tip: drow.modelData.mac
          onClicked: page.trustRequested(drow.modelData.mac, !drow.modelData.trusted)
        }
        Pill {
          visible: !drow.modelData.gateway && !!page.sentinel && page.sentinel.rootParts
          text: Skin.t("sentinel.block")
          onClicked: page.blockRequested(drow.modelData.ip)
        }
      }
    }

    SectionTitle {
      visible: !!page.fw && page.fw.blocked.length > 0
      text: Skin.t("sentinel.blockedList")
      Layout.topMargin: 6 * Skin.u
    }
    Repeater {
      model: page.fw ? page.fw.blocked : []
      delegate: ListRow {
        id: urow
        required property var modelData
        tone: Skin.urgent
        name: modelData
        alwaysShowActions: true
        Pill {
          text: Skin.t("sentinel.unblock")
          onClicked: page.unblockRequested(urow.modelData)
        }
      }
    }
  }
}

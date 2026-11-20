import QtQuick
import QtQuick.Layouts
import "."
import "Format.js" as F

// The Care page: what fills the disk and what can be freed, warnings, and
// pending updates, from `fathom-care status`.
GridLayout {
  id: page

  property var care: null
  // True while `fathom-care check` runs.
  property bool checking: false
  // Ids of items being cleaned.
  property var cleaning: ({})

  signal cleanRequested(var ids, bool needsRoot)
  signal restartRequested(string scope, string unit)
  signal logRequested(string scope, string unit)
  signal updateRequested()
  signal fathomUpdateRequested()
  signal checkRequested()
  signal wardSetupRequested()
  signal wardDismissRequested()
  signal wardOpenRequested()

  readonly property var disk: care ? care.disk : null
  readonly property var reclaim: care && Array.isArray(care.reclaim) ? care.reclaim : []
  readonly property var warnings: care && Array.isArray(care.warnings) ? care.warnings : []
  // The warnings that need you: the offer to set up Ward is listed with
  // them but isn't one, so it doesn't count.
  readonly property int needCount: {
    var n = 0
    for (var i = 0; i < warnings.length; i++) if (warnings[i].kind !== "ward-setup") n++
    return n
  }
  readonly property var updates: care ? care.updates : null
  readonly property var info: care ? care.info : null
  readonly property bool busyChecking: checking || (!!care && care.checking === true)
  readonly property int updateCount: F.updateCount(updates)
  // fathom-update's last check (Care only reads it; nothing is fetched).
  readonly property var fathomUpdate: care && care.fathom ? care.fathom : null
  readonly property bool fathomReady: !!fathomUpdate && fathomUpdate.available === true

  columns: 3
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  function segmentColor(key) {
    switch (key) {
    case "system": return Skin.blue
    case "docker": return Skin.accent
    case "models": return Skin.violet
    case "caches": return Skin.warn
    case "projects": return Skin.ok
    default: return Skin.tint(Skin.fg, 0.45)
    }
  }

  function agoText(then) {
    if (!care || !then) return ""
    var a = F.ago(then, care.time)
    return Skin.tn("care.ago." + a.unit, a.n).arg(Skin.n(a.n))
  }

  function askClean(items) {
    if (items.length === 0) return
    var names = []
    for (var i = 0; i < items.length; i++) names.push(Skin.t("care.reclaim." + items[i].id))
    var root = F.anyRoot(items)
    var chosen = F.ids(items)
    Skin.ask(
      Skin.t("care.confirmTitle").arg(Skin.size(F.totalBytes(items))),
      Skin.t("care.confirmBody").arg(names.join(", ")) + (root ? "\n\n" + Skin.t("care.confirmRoot") : ""),
      Skin.t("care.free"),
      function() { page.cleanRequested(chosen, root) })
  }

  function summary() {
    if (!care) return [{ tone: "stopped", text: Skin.t("loading") }]
    var out = []
    var need = 0
    for (var i = 0; i < warnings.length; i++) if (warnings[i].kind !== "disk" && warnings[i].kind !== "ward-setup") need++
    if (need > 0) out.push({ tone: "bad", text: Skin.tn("care.summary.warnings", need).arg(Skin.n(need)) })
    if (fathomReady) out.push({ tone: "warn", text: Skin.t("care.summary.fathom").arg(fathomUpdate.target) })
    if (updates) {
      out.push(updateCount > 0
        ? { tone: "warn", text: Skin.tn("care.summary.updates", updateCount).arg(Skin.n(updateCount)) }
        : { tone: "ok", text: Skin.t("care.summary.upToDate") })
    }
    if (disk) out.push({ tone: F.level(disk.pct), text: Skin.t("summary.disk").arg(Skin.n(disk.pct)) })
    if (out.length === 0 || (need === 0 && page.needCount === 0)) out.unshift({ tone: "ok", text: Skin.t("care.summary.clear") })
    return out
  }

  // ------------------------------------------------ Disk
  Card {
    Layout.preferredWidth: 1.25
    title: Skin.t("care.disk")
    glyph: ""
    subtitle: page.disk ? page.disk.model : ""

    Label {
      visible: !!page.disk
      text: page.disk ? Skin.t("care.diskUsed").arg(Skin.size(page.disk.used)).arg(Skin.size(page.disk.size)).arg(Skin.size(page.disk.free)) : ""
      font.pixelSize: 15 * Skin.u
      Layout.fillWidth: true
    }

    // What fills it, as one bar.
    Rectangle {
      visible: !!page.disk
      Layout.fillWidth: true
      height: 14 * Skin.u
      radius: 4 * Skin.u
      color: Skin.faint
      clip: true
      Row {
        anchors.fill: parent
        Repeater {
          model: F.diskSegments(page.disk)
          delegate: Rectangle {
            required property var modelData
            width: parent.width * modelData.share
            height: parent.height
            color: page.segmentColor(modelData.key)
          }
        }
        // Before the first check: just how full it is.
        Rectangle {
          visible: !!page.disk && !page.disk.breakdown
          width: page.disk ? parent.width * page.disk.pct / 100 : 0
          height: parent.height
          color: page.disk ? Skin.levelColor(F.level(page.disk.pct)) : Skin.accent
        }
      }
    }
    Flow {
      Layout.fillWidth: true
      spacing: 14 * Skin.u
      Repeater {
        model: F.diskSegments(page.disk)
        delegate: Row {
          required property var modelData
          spacing: 6 * Skin.u
          Rectangle {
            width: 9 * Skin.u
            height: width
            radius: 2 * Skin.u
            color: page.segmentColor(modelData.key)
            anchors.verticalCenter: parent.verticalCenter
          }
          Label {
            text: Skin.t("care.part." + modelData.key) + " " + Skin.size(modelData.bytes)
            color: Skin.dim
            font.pixelSize: 12 * Skin.u
          }
        }
      }
    }
    Label {
      readonly property var f: page.disk ? F.forecast(page.disk.forecastDays) : null
      visible: !!f
      text: f ? Skin.tn("care.forecast." + f.unit, f.n).arg(Skin.n(f.n)) : ""
      color: Skin.warn
      font.pixelSize: 13 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
    }

    SectionTitle {
      text: page.reclaim.length > 0 ? Skin.t("care.reclaimTitle").arg(Skin.size(F.totalBytes(page.reclaim))) : Skin.t("care.reclaimNone")
      Layout.topMargin: 8 * Skin.u
    }
    Empty {
      visible: !page.care || (!page.care.checkedAt && page.reclaim.length === 0)
      text: page.busyChecking ? Skin.t("care.measuring") : Skin.t("loading")
    }
    Repeater {
      model: page.reclaim
      delegate: ListRow {
        id: rrow
        required property var modelData
        readonly property bool working: page.cleaning[modelData.id] === true
        showDot: false
        name: Skin.t("care.reclaim." + modelData.id)
        detail: working ? Skin.t("care.cleaning") : Skin.t("care.reclaimDetail." + modelData.id)
        right1: Skin.size(modelData.bytes)
        right2: modelData.root ? Skin.t("care.needsPassword") : ""

        Pill {
          glyph: rrow.modelData.root ? "" : ""
          text: Skin.t("care.clean")
          tip: rrow.modelData.root ? Skin.t("care.needsPassword") : ""
          enabledAction: !rrow.working
          onClicked: page.askClean([rrow.modelData])
        }
      }
    }

    footer: [
      Pill {
        visible: page.reclaim.length > 0
        primary: true
        glyph: ""
        text: Skin.t("care.freeAll").arg(Skin.size(F.totalBytes(page.reclaim)))
        enabledAction: Object.keys(page.cleaning).length === 0
        onClicked: page.askClean(page.reclaim)
      },
      Item { Layout.fillWidth: true },
      Pill {
        glyph: ""
        text: page.busyChecking ? Skin.t("care.checking") : Skin.t("care.checkNow")
        enabledAction: !page.busyChecking
        onClicked: page.checkRequested()
      }
    ]
  }

  // ------------------------------------------------ Warnings
  Card {
    title: Skin.t("care.warnings")
    glyph: ""
    subtitle: page.needCount > 0 ? Skin.tn("care.needYou", page.needCount).arg(Skin.n(page.needCount)) : ""
    subtitleColor: page.needCount > 0 ? Skin.warn : Skin.dim

    Empty {
      visible: !!page.care && page.warnings.length === 0
      text: Skin.t("care.allClear")
    }
    Repeater {
      model: page.warnings
      delegate: ListRow {
        id: wrow
        required property var modelData
        readonly property bool isUnit: modelData.kind === "unit"
        readonly property bool isWardSetup: modelData.kind === "ward-setup"
        readonly property bool isWard: modelData.kind === "ward"
        alwaysShowActions: true
        tone: isWardSetup ? Skin.dim : isWard ? Skin.urgent
          : (modelData.kind === "disk" ? Skin.levelColor(modelData.level) : (isUnit ? Skin.urgent : Skin.warn))
        name: isWardSetup ? Skin.t("care.wardSetup")
          : isWard ? Skin.tn("care.wardNow", modelData.now).arg(Skin.n(modelData.now))
          : isUnit ? Skin.t("care.unitFailed").arg(modelData.description || modelData.unit)
          : (modelData.kind === "disk" ? Skin.t("care.diskFull").arg(Skin.n(modelData.pct))
          : Skin.t("care.reboot"))
        detail: isWardSetup ? Skin.t("care.wardSetupDetail")
          : isWard ? Skin.t("care.wardNowDetail")
          : isUnit ? Skin.t(modelData.scope === "user" ? "care.unitUser" : "care.unitSystem").arg(modelData.unit)
          : (modelData.kind === "disk" ? Skin.t("care.diskFullDetail") : Skin.t("care.rebootDetail"))

        Pill {
          visible: wrow.isWardSetup
          text: Skin.t("care.wardSetUp")
          primary: true
          onClicked: page.wardSetupRequested()
        }
        Pill {
          visible: wrow.isWardSetup
          text: Skin.t("care.wardNotNow")
          onClicked: page.wardDismissRequested()
        }
        Pill {
          visible: wrow.isWard
          glyph: "\uf2d0"
          tip: Skin.t("care.openWard")
          onClicked: page.wardOpenRequested()
        }

        Pill {
          visible: wrow.isUnit
          glyph: ""
          tip: Skin.t("care.restart")
          onClicked: page.restartRequested(wrow.modelData.scope, wrow.modelData.unit)
        }
        Pill {
          visible: wrow.isUnit
          glyph: ""
          tip: Skin.t("care.showLog")
          onClicked: page.logRequested(wrow.modelData.scope, wrow.modelData.unit)
        }
      }
    }

    SectionTitle { text: Skin.t("care.fyi"); Layout.topMargin: 8 * Skin.u }
    ListRow {
      visible: !!page.info && page.info.battery !== null
      tone: page.info && page.info.battery < 80 ? Skin.warn : Skin.ok
      name: Skin.t("care.battery").arg(page.info ? Skin.n(page.info.battery) : "")
      detail: page.info && page.info.cycles !== null ? Skin.tn("care.cycles", page.info.cycles).arg(Skin.n(page.info.cycles))
        + (page.info.battery < 80 ? " · " + Skin.t("care.batteryWorn") : "") : ""
    }
    ListRow {
      visible: !!page.info && page.info.cpuTemp !== null
      tone: page.info && page.info.cpuTemp >= 90 ? Skin.urgent : (page.info && page.info.cpuTemp >= 80 ? Skin.warn : Skin.ok)
      name: Skin.t("care.cpuTemp").arg(page.info ? Skin.n(page.info.cpuTemp) : "")
      detail: Skin.t("care.cpuTempNow")
    }
    ListRow {
      visible: !!page.info && page.info.lastUpdate !== null
      tone: Skin.ok
      name: Skin.t("care.lastUpdate").arg(page.info ? page.agoText(page.info.lastUpdate) : "")
      detail: page.info && page.info.lastUpdate ? new Date(page.info.lastUpdate * 1000).toLocaleDateString(Skin.locale, "dddd d MMMM") : ""
    }
    ListRow {
      visible: !!page.info
      tone: page.info && page.info.snapshots ? Skin.ok : Skin.dim
      name: page.info && page.info.snapshots ? Skin.t("care.snapshotsOn") : Skin.t("care.snapshotsOff")
      detail: page.info && page.info.snapshots ? Skin.t("care.snapshotsOnDetail") : Skin.t("care.snapshotsOffDetail")
    }
  }

  // ------------------------------------------------ Updates
  Card {
    title: Skin.t("care.updates")
    glyph: ""
    subtitle: page.updates && page.updateCount > 0
      ? Skin.size(page.updates.download) + (page.updates.restart ? " · " + Skin.t("care.restartAfter") : "") : ""

    Empty {
      visible: !page.updates
      text: page.busyChecking ? Skin.t("care.lookingForUpdates")
        : (!!page.care && page.care.updatesStale === true ? Skin.t("care.updatesChanged") : Skin.t("loading"))
    }
    Empty {
      visible: !!page.updates && page.updateCount === 0
      text: Skin.t("care.upToDate")
    }

    ListRow {
      visible: !!page.updates && page.updates.packages.length > 0
      tone: page.updates && page.updates.kernel ? Skin.warn : Skin.accent
      name: Skin.t("care.systemPackages")
      detail: page.updates && page.updates.kernel ? Skin.t("care.includesKernel") : ""
      right1: page.updates ? Skin.n(page.updates.packages.length) : ""
    }
    ListRow {
      visible: !!page.updates && page.updates.aur.length > 0
      tone: Skin.accent
      name: Skin.t("care.aur")
      right1: page.updates ? Skin.n(page.updates.aur.length) : ""
    }
    ListRow {
      visible: !!page.updates && page.updateCount > 0
      tone: page.updates && page.updates.firmware > 0 ? Skin.accent : Skin.ok
      name: Skin.t("care.firmware")
      right1: page.updates && page.updates.firmware > 0 ? Skin.n(page.updates.firmware) : Skin.t("care.firmwareCurrent")
    }
    ListRow {
      visible: page.fathomReady || (!!page.fathomUpdate && !!page.fathomUpdate.blocked)
      tone: page.fathomReady ? Skin.accent : Skin.warn
      name: "Fathom"
      detail: !page.fathomUpdate ? "" : (page.fathomReady
        ? Skin.tn("care.fathomChanges", page.fathomUpdate.commits.length).arg(Skin.n(page.fathomUpdate.commits.length))
          + (page.fathomUpdate.needsPassword ? " · " + Skin.t("care.needsPassword") : "")
        : page.fathomUpdate.blocked)
      right1: page.fathomReady ? String(page.fathomUpdate.target) : ""
    }
    ListRow {
      visible: !!page.updates && !!page.updates.omarchy
      tone: Skin.violet
      name: "Omarchy"
      detail: page.updates && page.updates.omarchy ? Skin.t("care.version").arg(page.updates.omarchy.from).arg(page.updates.omarchy.to) : ""
    }

    SectionTitle {
      visible: !!page.updates && page.updateCount > 0
      text: Skin.t("care.whatsNew")
      Layout.topMargin: 6 * Skin.u
    }
    Repeater {
      model: page.updates ? page.updates.packages.concat(page.updates.aur).slice(0, 8) : []
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 8 * Skin.u
        Label { text: modelData.name; font.pixelSize: 13 * Skin.u; Layout.fillWidth: true }
        Label { text: modelData.to; color: Skin.dim; font.pixelSize: 12 * Skin.u; Layout.maximumWidth: 150 * Skin.u }
      }
    }
    Label {
      readonly property int more: page.updates ? page.updates.packages.length + page.updates.aur.length - 8 : 0
      visible: more > 0
      text: Skin.tn("care.more", more).arg(Skin.n(more))
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
    }

    Label {
      visible: !!page.updates && page.updateCount > 0
      text: page.info && page.info.snapshots ? Skin.t("care.updateSafety") : Skin.t("care.updateSafetyNoSnapshot")
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      Layout.fillWidth: true
      Layout.topMargin: 6 * Skin.u
    }

    footer: [
      Pill {
        visible: !!page.updates && page.updateCount > 0
        primary: true
        glyph: ""
        text: Skin.t("care.updateAll")
        onClicked: page.updateRequested()
      },
      Pill {
        visible: page.fathomReady
        primary: page.updateCount === 0
        text: Skin.t("care.updateFathom")
        tip: page.fathomReady && page.fathomUpdate.needsPassword ? Skin.t("care.needsPassword") : ""
        onClicked: page.fathomUpdateRequested()
      },
      Item { Layout.fillWidth: true },
      Label {
        visible: !!page.care && !!page.care.checkedAt
        text: page.care && page.care.checkedAt ? Skin.t("care.checked").arg(page.agoText(page.care.checkedAt)) : ""
        color: Skin.dim
        font.pixelSize: 12 * Skin.u
      }
    ]
  }
}

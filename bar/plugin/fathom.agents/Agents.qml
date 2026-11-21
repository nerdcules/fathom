import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Agents.js" as A

// Fathom's Agents on the bar (#14): Omarchy's Agents icon, with Fathom's
// own dropdown under it. A clone of omarchy.agents (manifest.json): turning
// it on puts it where Omarchy's was, with its settings (the providers it
// shows, refreshIntervalSec, sync); turning it off puts Omarchy's back. It
// answers to omarchy.agents as Omarchy's does (`omarchy-shell
// omarchy.agents open|close|toggle|refresh`).
//
// The usage records are read by Omarchy's own Main.qml and Agent.qml,
// copied unchanged: the records omarchy-agent-usage-update writes, its
// refresh timer, the order the agents were dragged into, and synced
// snapshots from other machines. The dropdown shows each subscription's
// limits (Agents.js), its accounts when it has several (Use, Autoswitch),
// its balance when it's prepaid, and Omarchy's starters; its actions run
// Omarchy's own commands. Signing in (adding an account, or again when a
// sign-in lapsed) opens Omarchy's sign-in in a terminal, where it asks for
// what it needs, instead of following it inside the dropdown as Omarchy's
// panel does.
//
// The button: a click opens the dropdown, a right-click starts an agent
// (omarchy-agent --pick), a middle-click fetches the usage again. It lights
// when a limit is 90% used or a prepaid balance is down to its last 10%.
Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  // Fathom's words, and Omarchy's for keys that start with "@".
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }
  function tn(key, n) { return Commons.I18n.tn(key.charAt(0) === "@" ? key.substring(1) : key, n) }
  function num(n, decimals) { return decimals ? Commons.I18n.formatNumber(n, decimals) : Commons.I18n.formatNumber(n) }

  Main {
    id: usage
    settings: root.settings
  }

  // "Resets in 2h" keeps telling the truth while the dropdown is open.
  property double nowMs: Date.now()
  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: root.nowMs = Date.now() }

  // The line under the title turns through what the token counts add up to.
  readonly property var phrases: {
    var rev = usage.dataRevision
    return A.summaryPhrases(usage.enabledProviders, root.tn, root.t, root.num,
      function(id) { return usage.friendlyModelName(id) }, function(n) { return usage.formatTokenCount(n) },
      function(date) {
        var d = new Date(String(date || "") + "T00:00:00")
        return isNaN(d.getTime()) ? String(date || "") : Qt.locale(Commons.I18n.formatLocale).dayName([7, 1, 2, 3, 4, 5, 6][d.getDay()])
      })
  }
  property int phraseIndex: 0
  Timer { interval: 2800; running: root.opened && root.phrases.length > 1; repeat: true; onTriggered: root.phraseIndex++ }

  readonly property bool alarming: A.alarming(usage.subscribedProviders, nowMs)
  property bool adding: false

  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    var list = usage.enabledProviders
    for (var i = 0; i < list.length; i++) {
      var count = Number(list[i].syncDeviceCount || 0)
      if (list[i].syncEnabled && count > 0) return A.fill(tn("@agents.merged", count), num(count))
    }
    return ""
  }
  // The agent's mark, from Omarchy's own: the white one on a dark panel,
  // its -light twin on a light one (where an agent ships one).
  function iconFor(id) {
    var bg = Skin.bg
    var light = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b >= 0.5
    return "file://" + Quickshell.shellDir + "/plugins/agents/assets/" + id + (light ? "-light" : "") + ".svg"
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }
  // Omarchy's sign-in, in a terminal: it asks for a name for a further
  // account, opens the browser, and takes a pasted code when the page shows
  // one.
  function signIn(args) {
    root.close()
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", "omarchy-agent-account-add " + args])
  }
  function providerById(id) {
    var list = usage.subscribedProviders
    for (var i = 0; i < list.length; i++) if (list[i].providerId === id) return list[i]
    return null
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      adding = false
      usage.refreshLimits()
      if (panel.loadedContent) panel.loadedContent.rest()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ShellIpc {
    target: "omarchy.agents"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { usage.refreshAll(true); return "ok" }
  }

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF16A3)
    active: root.alarming
    onPressed: function(b) {
      if (b === Qt.RightButton) root.launchAgent()
      else if (b === Qt.MiddleButton) usage.refreshAll(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    padding: 0
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.round(380 * Skin.u))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(860 * Skin.u))

    content: DropCard {
      title: root.t("@agents.title")
      subtitle: root.phrases.length > 0 ? root.phrases[root.phraseIndex % root.phrases.length] : root.t("@agents.subscriptions")
      glyph: String.fromCodePoint(0xF16A3)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: {
          var rev = usage.dataRevision
          return A.sections({
            providers: usage.subscribedProviders, now: root.nowMs, adding: root.adding,
            footer: root.footerText(), iconFor: root.iconFor
          }, root.t, root.tn, root.num)
        }
        onPicked: function(key, value) {
          var parts = key.split(" ")
          if (key === "do") {
            if (value === "launch") root.launchAgent()
            else if (value === "add") root.adding = !root.adding
          } else if (key === "add") root.signIn(value)
          else if (key === "signin") root.signIn("--reauth :primary " + value)
          else if (key === "starter") { root.close(); Util.execArgv(["omarchy-agent-prompt", A.starterPrompt(value)]) }
          else if (parts[0] === "account") Util.execArgv(["omarchy-agent-account-use", parts[1], value])
        }
        onToggled: function(key, on) {
          var parts = key.split(" ")
          if (parts[0] !== "autoswitch") return
          // As Omarchy's: set the mode, then fetch that agent's limits again.
          Util.execArgv(["bash", "-c", 'omarchy-agent-account-mode "$1" "$2" >/dev/null && omarchy-agent-usage-update --limits-only "$1"',
                         "omarchy-agent-account-mode", parts[1], on ? "auto" : "manual"])
        }
      }
    }
  }
}

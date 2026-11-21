import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Tailscale.js" as T

// Fathom's Tailscale on the bar (#14): Omarchy's Tailscale icon, with
// Fathom's own dropdown under it. A clone of omarchy.tailscale
// (manifest.json): turning it on puts it where Omarchy's was, with its
// settings; turning it off puts Omarchy's back. It answers to
// omarchy.tailscale as Omarchy's does (`omarchy-shell omarchy.tailscale
// open|close|toggle|refresh|up|down|toggleTailscale|status`).
//
// Tailscale is run by Omarchy's own Service.qml and Model.js, copied
// unchanged: the status poll every refreshIntervalSec (setting, default
// 30), turning it on and off (and logging in), switching accounts, exit
// nodes and Mullvad regions, copying with wl-copy, Taildrop through
// omarchy-tailscale-send. The exit-node list and the recent Mullvad regions
// are built as Omarchy's panel builds them (its Panel.qml, MIT).
//
// The button: a click opens the dropdown, a right-click turns Tailscale on
// or off, a middle-click fetches its state again.
Panel {
  id: root
  moduleName: "omarchy.tailscale"
  ipcTarget: "omarchy.tailscale"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  // Fathom's words, and Omarchy's for keys that start with "@".
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }

  Service {
    id: tailscale
    settings: root.settings
    peersWanted: root.opened
  }

  // ---- The machines.
  property string peerQuery: ""
  property int peerIndex: 0
  readonly property var shownPeers: T.filterPeers(tailscale.peers, peerQuery).slice(0, T.MACHINE_LIMIT)
  readonly property var chosenPeer: shownPeers.length > 0 ? shownPeers[Math.max(0, Math.min(peerIndex, shownPeers.length - 1))] : null

  // ---- Exit nodes, as Omarchy's panel lists them: the tailnet's, then up
  // to five Mullvad regions (the one in use, then the recent ones), then a
  // row that opens the Mullvad search.
  property bool mullvadOpen: false
  property string mullvadQuery: ""
  property int regionIndex: 0
  readonly property var recentRegions: settings.recentMullvadRegions instanceof Array ? settings.recentMullvadRegions
    : (settings.recentMullvadCountries instanceof Array ? settings.recentMullvadCountries : [])
  readonly property var exitNodes: {
    var nodes = tailscale.tailnetExitNodes.slice()
    var seen = {}
    var mullvad = []
    for (var a = 0; a < tailscale.mullvadRegions.length && mullvad.length < 5; a++) {
      var on = tailscale.mullvadRegions[a]
      var onKey = regionKey(on)
      if (on.ExitNode === true && onKey !== "" && !seen[onKey]) { mullvad.push(on); seen[onKey] = true }
    }
    for (var i = 0; i < recentRegions.length && mullvad.length < 5; i++) {
      var key = String(recentRegions[i] || "")
      if (key === "" || seen[key]) continue
      var node = regionNode(key)
      if (node) { mullvad.push(node); seen[key] = true }
    }
    nodes = nodes.concat(mullvad)
    if (tailscale.mullvadRegions.length > 0) nodes.push({ id: "mullvad:add", AddMullvad: true })
    return nodes
  }
  function regionKey(node) {
    if (!node) return ""
    var country = String(node.Country || ""), city = String(node.City || "")
    return country === "" || city === "" ? "" : country + "\n" + city
  }
  function regionNode(key) {
    for (var i = 0; i < tailscale.mullvadRegions.length; i++) {
      var node = tailscale.mullvadRegions[i]
      if (regionKey(node) === key || String(node.Country || "") === key) return node
    }
    return null
  }
  function nodeById(list, id) {
    for (var i = 0; i < list.length; i++) if (String(list[i].id || "") === String(id)) return list[i]
    return null
  }
  // The region just used goes first in the entry's recentMullvadRegions.
  function rememberRegion(key) {
    if (key === "") return
    var next = [key]
    for (var i = 0; i < recentRegions.length && next.length < 5; i++) {
      var k = String(recentRegions[i] || "")
      if (k !== "" && next.indexOf(k) === -1) next.push(k)
    }
    var entry = { id: root.moduleName }
    for (var name in root.settings) if (name !== "id") entry[name] = root.settings[name]
    entry.recentMullvadRegions = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function chooseExit(node) {
    if (!node) return
    if (node.Mullvad === true) rememberRegion(regionKey(node))
    tailscale.setExitNode(node)
    mullvadOpen = false
  }

  // ---- Copying, with a word to say it happened.
  property string copied: ""
  Timer { id: copiedTimer; interval: 2000; onTriggered: root.copied = "" }
  function peerAction(kind) {
    var p = chosenPeer
    if (!p) return
    var value = ""
    if (kind === "ip") { tailscale.copyPeerIp(p); value = (p.TailscaleIPs || [])[0] || "" }
    else if (kind === "name") { tailscale.copyPeerName(p); value = String(p.DisplayName || "") }
    else if (kind === "dns") { tailscale.copyPeerDnsName(p); value = String(p.DNSName || "") }
    else if (kind === "ipv6") { value = (p.TailscaleIPv6 || [])[0] || ""; tailscale.copyToClipboard(value, "IPv6") }
    else if (kind === "send") { tailscale.sendFile(p); return }
    if (value === "") return
    copied = T.fill(t("ts.copied"), value)
    copiedTimer.restart()
  }

  onOpenedChanged: {
    if (opened) {
      tailscale.refresh(false, true)
      if (panel.loadedContent) panel.loadedContent.rest()
    } else {
      // A query mustn't outlive the dropdown: reopening to a filtered list
      // looks like machines are missing (Omarchy's rule).
      peerQuery = ""; peerIndex = 0; mullvadOpen = false; mullvadQuery = ""; regionIndex = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ShellIpc {
    target: "omarchy.tailscale"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { tailscale.refresh(false, true); return "ok" }
    function up(): string { tailscale.loginOrUp(); return "ok" }
    function down(): string { tailscale.down(); return "ok" }
    function toggleTailscale(): string { tailscale.toggleTailscale(); return "ok" }
    function status(): string { return tailscale.statusText }
  }

  DropTheme { strings: catalog; screen: panel.screen }

  readonly property color barIconColor: tailscale.active ? barForeground : Qt.darker(barForeground, 1.55)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        TailscaleIcon {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          iconSize: button.iconSize
          color: root.barIconColor
          badgeColor: root.bar ? root.bar.urgent : Commons.Color.urgent
          crossed: !tailscale.active && !tailscale.needsLogin
          warning: tailscale.needsLogin
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) tailscale.toggleTailscale()
      else if (b === Qt.MiddleButton) tailscale.refresh(false, true)
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
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(680 * Skin.u))

    content: DropCard {
      title: tailscale.installed && tailscale.selfName !== "" ? tailscale.selfName : "Tailscale"
      subtitle: !tailscale.installed ? "" : tailscale.active ? [tailscale.selfIp, tailscale.selectedAccountLabel].filter(function(s) { return s !== "" }).join(" · ")
        : (tailscale.needsLogin ? root.t("@tailscale.authorizeDevice") : root.t("@tailscale.disconnectedMeta"))
      glyph: String.fromCodePoint(0xF0582)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
      keyHandler: function(e) {
        var act = T.keyAction(e.key, e.text)
        if (act === "toggle") tailscale.toggleTailscale()
        else if (act === "refresh") tailscale.refresh(false, true)
        else if (act === "ip" || act === "name" || act === "dns" || act === "send") root.peerAction(act)
        else if (act === "search") return panel.loadedContent.focusPart("machines")
        else return false
        return true
      }

      DropSections {
        width: parent.width
        model: T.sections({
          installed: tailscale.installed, active: tailscale.active, needsLogin: tailscale.needsLogin,
          status: tailscale.active ? root.t("ts.connected") : (tailscale.needsLogin ? root.t("@tailscale.authorizeDevice") : root.t("ts.disconnected")),
          message: root.copied !== "" ? root.copied : (tailscale.actionStatus !== "" ? tailscale.actionStatus : tailscale.lastError),
          error: root.copied === "" && tailscale.actionStatus === "" && tailscale.lastError !== "",
          accounts: tailscale.accounts.map(function(a) { return { id: a.id, label: tailscale.accountLabel(a) } }),
          accountId: tailscale.selectedAccountId, switchingId: tailscale.switchingAccountId,
          showAccounts: tailscale.active && (tailscale.accounts.length > 1 || tailscale.accountsAccessDenied),
          operatorDenied: tailscale.accountsAccessDenied,
          exitNodes: root.exitNodes, exitBusyId: tailscale.settingExitNodeId,
          mullvadOpen: root.mullvadOpen, mullvadQuery: root.mullvadQuery, regions: tailscale.mullvadRegions,
          regionIndex: root.regionIndex,
          peersLoaded: tailscale.peersLoaded, peers: tailscale.peers, query: root.peerQuery, peerIndex: root.peerIndex,
          chosenPeer: root.chosenPeer, canSend: tailscale.canSendFiles(root.chosenPeer), osIcon: tailscale.osIcon
        }, root.t)
        onToggled: function(key, on) { if (key === "power") tailscale.toggleTailscale() }
        onPicked: function(key, value) {
          if (key === "account") {
            if (value === "@operator") tailscale.authorizeTailscaleOperator()
            else tailscale.switchAccount(value)
          } else if (key === "exit") {
            if (value === "mullvad:add" || value === "@mullvad") { root.mullvadOpen = !root.mullvadOpen; root.regionIndex = 0 }
            else root.chooseExit(root.nodeById(root.exitNodes, value))
          } else if (key === "region") root.chooseExit(root.nodeById(tailscale.mullvadRegions, value))
          else if (key === "machines") {
            for (var i = 0; i < root.shownPeers.length; i++) if (String(root.shownPeers[i].id) === value) root.peerIndex = i
          } else if (key === "peer") root.peerAction(value)
        }
        onEdited: function(key, text) {
          if (key === "machines") { root.peerQuery = text; root.peerIndex = 0 }
          else if (key === "region") { root.mullvadQuery = text; root.regionIndex = 0 }
        }
        onMoved: function(key, value) {
          if (key === "machines") root.peerIndex = value
          else if (key === "region") root.regionIndex = value
        }
        onSubmitted: function(key, values) {
          if (key === "machines") { root.peerIndex = values.chosen; root.peerAction("ip") }
          else if (key === "region") {
            var regions = T.filterRegions(tailscale.mullvadRegions, root.mullvadQuery)
            root.chooseExit(regions[values.chosen])
          }
        }
        onCancelled: function(key) {
          if (key === "region") { root.mullvadOpen = false; root.mullvadQuery = "" }
          else if (key === "machines" && root.peerQuery !== "") { root.peerQuery = ""; root.peerIndex = 0 }
          if (panel.loadedContent) panel.loadedContent.rest()
        }
      }
    }
  }
}

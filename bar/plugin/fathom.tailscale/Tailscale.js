.pragma library

// Fathom's Tailscale dropdown (#14): what it shows, as the kit's factory
// draws it. Tailscale itself is run by Omarchy's Service.qml (copied); the
// machines, exit nodes and accounts are its. Node tests: tests/bar.test.mjs.
//
// `t` turns a key into words: Fathom's own keys from i18n/en.json, and keys
// starting with "@" from Omarchy's catalog (its Tailscale words, in every
// language Omarchy has).

// "%1 of %2" filled in, as QML's arg() does.
function fill(s) {
  var out = String(s)
  for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
  return out
}

// The most machines drawn at once; typing narrows the rest.
var MACHINE_LIMIT = 40

// The machines matching `query` (name, DNS name or IPv4), as Omarchy's panel
// filters them.
function filterPeers(peers, query) {
  var q = String(query || "").trim().toLowerCase()
  var list = peers || []
  if (q === "") return list.slice()
  return list.filter(function(p) {
    var ip = p.TailscaleIPs && p.TailscaleIPs.length > 0 ? String(p.TailscaleIPs[0]) : ""
    return (String(p.DisplayName || "") + " " + String(p.DNSName || "") + " " + ip).toLowerCase().indexOf(q) !== -1
  })
}

// Mullvad regions matching `query` (city or country), as Omarchy's.
function filterRegions(regions, query) {
  var q = String(query || "").trim().toLowerCase()
  return (regions || []).filter(function(r) {
    return q === "" || (String(r.City || "") + " " + String(r.Country || "")).toLowerCase().indexOf(q) !== -1
  })
}

// One machine's second line: its address, its system, and offline when it is.
function peerDetail(p, t) {
  var parts = []
  if (p.TailscaleIPs && p.TailscaleIPs.length > 0) parts.push(String(p.TailscaleIPs[0]))
  if (p.OS) parts.push(String(p.OS))
  if (p.Online !== true) parts.push(t("ts.offline"))
  return parts.join(" · ")
}

// What can be copied from a machine, and whether files can go to it.
function peerActions(p, canSend, t) {
  if (!p) return []
  var out = []
  if (p.TailscaleIPs && p.TailscaleIPs.length > 0) out.push({ key: "ip", label: t("ts.copyIp"), glyph: String.fromCodePoint(0xF018F), primary: true })
  if (p.DisplayName) out.push({ key: "name", label: t("ts.copyName") })
  if (p.DNSName) out.push({ key: "dns", label: t("ts.copyDns") })
  if (p.TailscaleIPv6 && p.TailscaleIPv6.length > 0) out.push({ key: "ipv6", label: t("ts.copyIpv6") })
  if (canSend) out.push({ key: "send", label: t("@tailscale.sendFiles"), glyph: String.fromCodePoint(0xF048A) })
  return out
}

// An exit node's row: a tailnet machine, a Mullvad region, or the row that
// opens the Mullvad search.
function exitRow(n, busyId, t) {
  if (n.AddMullvad === true)
    return { key: "@mullvad", glyph: "+", name: t("@tailscale.chooseMullvadRegion"), detail: "", clickable: true }
  var mullvad = n.Mullvad === true
  var city = String(n.City || "").trim()
  var name = mullvad && city !== "" && city !== "Any" ? city : String(n.DisplayName || n.HostName || t("@tailscale.unknown"))
  var detail = mullvad ? String(n.Country || "") : (n.Online === false ? t("ts.offline") : "")
  return {
    key: String(n.id || ""), glyph: String.fromCodePoint(mullvad ? 0xF0582 : 0xF11E2),
    name: name, detail: detail, active: n.ExitNode === true, busy: busyId !== "" && busyId === String(n.id || ""),
    clickable: true
  }
}

// `v`: installed, active, needsLogin, busy, status (words for the state),
// message (an action's progress or the last error), error (true when it's
// an error), accounts ([{id, label}]), accountId, switchingId, showAccounts,
// operatorDenied, exitNodes (Omarchy's display list), exitBusyId,
// mullvadOpen, mullvadQuery, regions, regionIndex, peersLoaded, peers (all),
// query, peerIndex, chosenPeer, canSend, osIcon (os -> glyph).
function sections(v, t) {
  var peers = filterPeers(v.peers, v.query)
  var shown = peers.slice(0, MACHINE_LIMIT)
  var regions = filterRegions(v.regions, v.mullvadQuery).slice(0, MACHINE_LIMIT)
  var total = (v.peers || []).length
  var countLabel = String(v.query || "").trim() !== ""
    ? fill(t("@tailscale.machinesFiltered"), peers.length, total)
    : fill(t("@tailscale.machinesCount"), total)
  var accountRows = (v.accounts || []).map(function(a) {
    return { key: String(a.id), glyph: String.fromCodePoint(0xEB01), name: String(a.label || a.id),
             active: String(a.id) === String(v.accountId || ""), busy: String(a.id) === String(v.switchingId || "") }
  })
  if (v.operatorDenied)
    accountRows.unshift({ key: "@operator", glyph: String.fromCodePoint(0xF0483), name: t("@tailscale.authorizeOperator"),
                          detail: t("@tailscale.authorizeHelp") })
  return [
    { type: "text", hidden: !!v.installed, text: t("@tailscale.notInstalled"), dim: true },
    { type: "switch", key: "power", hidden: !v.installed, glyph: String.fromCodePoint(0xF0582), name: "Tailscale",
      detail: v.status || "", on: !!v.active },
    { type: "text", hidden: !v.message, text: v.message || "", dim: !v.error },
    { type: "rows", key: "account", title: t("@tailscale.connections"), hidden: !v.showAccounts, rows: accountRows },
    { type: "rows", key: "exit", title: t("@tailscale.exitNodes"), hidden: !v.active || (v.exitNodes || []).length === 0,
      rows: (v.exitNodes || []).map(function(n) { return exitRow(n, v.exitBusyId || "", t) }) },
    { type: "search", key: "region", hidden: !v.active || !v.mullvadOpen, text: v.mullvadQuery || "",
      placeholder: t("@tailscale.searchRegions"),
      results: regions.map(function(r) { return { key: String(r.id || ""), name: String(r.City || ""), detail: String(r.Country || "") } }),
      chosen: Math.min(v.regionIndex || 0, Math.max(0, regions.length - 1)) },
    { type: "text", hidden: !v.active || !v.mullvadOpen || regions.length > 0, text: t("@tailscale.noRegions"), dim: true },
    { type: "search", key: "machines", hidden: !v.active || !v.peersLoaded || total === 0, text: v.query || "", autoFocus: false,
      placeholder: countLabel,
      results: shown.map(function(p) {
        return { key: String(p.id || ""), glyph: v.osIcon ? v.osIcon(p.OS) : "", name: String(p.DisplayName || ""), detail: peerDetail(p, t) }
      }),
      chosen: Math.min(v.peerIndex || 0, Math.max(0, shown.length - 1)) },
    { type: "text", hidden: !v.active || peers.length <= MACHINE_LIMIT, dim: true,
      text: fill(t("ts.more"), MACHINE_LIMIT, peers.length) },
    { type: "actions", key: "peer", hidden: !v.active || !v.chosenPeer,
      buttons: peerActions(v.chosenPeer, !!v.canSend, t) },
    { type: "text", hidden: !v.active || v.peersLoaded, text: t("@tailscale.loadingMachines"), dim: true },
    { type: "text", hidden: !v.active || !v.peersLoaded || total > 0, text: t("@tailscale.noMachines"), dim: true },
    { type: "text", hidden: !v.active || total === 0 || peers.length > 0, text: t("@tailscale.noMatchingMachines"), dim: true }
  ]
}

// The card's letter keys, as Omarchy's panel has them, while the keyboard
// isn't in a search field: t on or off, r fetch again, c n d copy the
// chosen machine's IP, name or DNS name, s send it files, / search.
function keyAction(key, text) {
  var c = String(text || "")
  if (c === "t" || c === "T") return "toggle"
  if (c === "r" || c === "R") return "refresh"
  if (c === "c" || c === "C") return "ip"
  if (c === "n" || c === "N") return "name"
  if (c === "d" || c === "D") return "dns"
  if (c === "s" || c === "S") return "send"
  if (c === "/") return "search"
  return ""
}

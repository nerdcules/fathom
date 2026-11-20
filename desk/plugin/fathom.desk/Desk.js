.pragma library

// The desk's logic: which windows Alt+Tab and Task view show and in what
// order, where a snap zone falls on the screen, and the Hyprland commands
// that act on them. No QML imports, so the tests can load it with node.
//
// Everything that goes into a Hyprland command is checked here first: an
// address must look like 0x1a2b, a workspace like a number, a size like a
// whole number. Window titles never go into a command.

// ---------------------------------------------------------------- windows

var MINIMIZED = "special:minimized"

function validAddress(a) {
  return typeof a === "string" && /^0x[0-9a-fA-F]{1,16}$/.test(a)
}

function validWorkspace(id) {
  return typeof id === "number" && isFinite(id) && Math.floor(id) === id && id >= 1 && id <= 9999
}

function plainText(v, max) {
  var s = String(v === undefined || v === null ? "" : v)
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ")
  return s.length > max ? s.slice(0, max) : s
}

// The workspace a minimized window came from, from Omarchy's tag on it.
function minimizedFrom(tags) {
  if (!Array.isArray(tags)) return null
  for (var i = 0; i < tags.length; i++) {
    var m = /^omarchy-minimized-from-([0-9]{1,4})$/.exec(String(tags[i]))
    if (m) return Number(m[1])
  }
  return null
}

function pair(v) {
  return Array.isArray(v) && v.length === 2 ? [Number(v[0]) || 0, Number(v[1]) || 0] : [0, 0]
}

// `hyprctl clients -j` reduced to the windows a person would switch to, most
// recently used first: those on ordinary workspaces, and minimized ones.
// Scratchpads and other special workspaces stay out, as do unmapped windows.
function windowList(clients) {
  if (!Array.isArray(clients)) return []
  var out = []
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i]
    if (!c || typeof c !== "object" || !validAddress(c.address)) continue
    if (c.mapped === false) continue
    var ws = c.workspace || {}
    var wsName = String(ws.name || "")
    var minimized = wsName === MINIMIZED
    if (!minimized && !validWorkspace(ws.id)) continue
    var history = Number(c.focusHistoryID)
    out.push({
      address: c.address,
      title: plainText(c.title, 300),
      appClass: plainText(c["class"] || c.initialClass, 120),
      workspace: minimized ? (minimizedFrom(c.tags) || 0) : ws.id,
      minimized: minimized,
      floating: c.floating === true,
      fullscreen: Number(c.fullscreen) > 0,
      at: pair(c.at),
      size: pair(c.size),
      monitor: Number(c.monitor) || 0,
      history: isFinite(history) && history >= 0 ? history : 1e6
    })
  }
  out.sort(function(a, b) { return a.history - b.history || (a.address < b.address ? -1 : 1) })
  return out
}

// One window per workspace grouping for Task view, workspaces in order.
function byWorkspace(windows) {
  var groups = {}
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (w.minimized) continue
    if (!groups[w.workspace]) groups[w.workspace] = []
    groups[w.workspace].push(w)
  }
  return groups
}

// The workspaces Task view shows: every ordinary one Hyprland knows, in
// order, from `hyprctl workspaces -j`.
function workspaceList(workspaces, activeId) {
  var out = []
  if (Array.isArray(workspaces)) {
    for (var i = 0; i < workspaces.length; i++) {
      var w = workspaces[i]
      if (w && validWorkspace(w.id)) out.push({ id: w.id, windows: Number(w.windows) || 0 })
    }
  }
  if (validWorkspace(activeId) && !out.some(function(w) { return w.id === activeId }))
    out.push({ id: activeId, windows: 0 })
  out.sort(function(a, b) { return a.id - b.id })
  return out
}

// The lowest workspace number not in use, for "New workspace".
function freeWorkspace(list) {
  var used = {}
  for (var i = 0; i < list.length; i++) used[list[i].id] = true
  for (var n = 1; n < 10000; n++) if (!used[n]) return n
  return 0
}

// Alt+Tab: the first press picks the window used before this one, as on
// Windows; later presses step on, wrapping round. Backwards from the start
// picks the last.
function stepIndex(current, count, delta, opening) {
  if (count <= 0) return -1
  if (opening) {
    if (count === 1) return 0
    return delta < 0 ? count - 1 : 1
  }
  var i = (current + delta) % count
  return i < 0 ? i + count : i
}

// Cards in a grid: how many across for `count` cards of aspect `aspect`
// (width / height) to fill `width` x `height` as large as they can.
function gridFit(count, width, height, aspect, gap) {
  if (count <= 0 || width <= 0 || height <= 0) return { columns: 1, cardWidth: 0, cardHeight: 0 }
  var best = { columns: 1, cardWidth: 0, cardHeight: 0 }
  for (var cols = 1; cols <= count; cols++) {
    var rows = Math.ceil(count / cols)
    var w = (width - gap * (cols - 1)) / cols
    var h = w / aspect
    if (h * rows + gap * (rows - 1) > height) {
      h = (height - gap * (rows - 1)) / rows
      w = h * aspect
    }
    if (w > best.cardWidth) best = { columns: cols, cardWidth: Math.floor(w), cardHeight: Math.floor(h) }
  }
  return best
}

// Where a window sits inside a small picture of its monitor, as fractions,
// clipped to the monitor (scrolling layouts park windows off to the side).
function miniRect(win, monitor) {
  if (!monitor || !(monitor.width > 0) || !(monitor.height > 0)) return null
  var x0 = Math.max(win.at[0] - monitor.x, 0)
  var y0 = Math.max(win.at[1] - monitor.y, 0)
  var x1 = Math.min(win.at[0] + win.size[0] - monitor.x, monitor.width)
  var y1 = Math.min(win.at[1] + win.size[1] - monitor.y, monitor.height)
  if (x1 <= x0 || y1 <= y0) return null
  return { x: x0 / monitor.width, y: y0 / monitor.height, w: (x1 - x0) / monitor.width, h: (y1 - y0) / monitor.height }
}

// ---------------------------------------------------------------- snapping

// Each zone is [x, y, width, height] as fractions of the usable screen.
var LAYOUTS = [
  { id: "halves", zones: [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1]] },
  { id: "wideLeft", zones: [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]] },
  { id: "thirds", zones: [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]] },
  { id: "mainStack", zones: [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]] },
  { id: "quarters", zones: [[0, 0, 1 / 2, 1 / 2], [1 / 2, 0, 1 / 2, 1 / 2], [0, 1 / 2, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]] },
  { id: "focus", zones: [[1 / 6, 0, 2 / 3, 1]] }
]

// The part of a monitor windows may use, in Hyprland's layout pixels:
// `hyprctl monitors -j` gives the size in device pixels, the scale, the
// position, and what the bar reserves on each side ([left, top, right,
// bottom]).
function usableArea(monitor, gapsOut) {
  if (!monitor) return null
  var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
  var transform = Number(monitor.transform) || 0
  var w = (Number(monitor.width) || 0) / scale
  var h = (Number(monitor.height) || 0) / scale
  if (transform % 2 === 1) { var t = w; w = h; h = t }
  var r = Array.isArray(monitor.reserved) ? monitor.reserved : [0, 0, 0, 0]
  var g = Math.max(0, Number(gapsOut) || 0)
  var left = (Number(r[0]) || 0) + g, top = (Number(r[1]) || 0) + g
  var right = (Number(r[2]) || 0) + g, bottom = (Number(r[3]) || 0) + g
  var area = {
    x: Math.round((Number(monitor.x) || 0) + left),
    y: Math.round((Number(monitor.y) || 0) + top),
    width: Math.round(w - left - right),
    height: Math.round(h - top - bottom)
  }
  return area.width > 0 && area.height > 0 ? area : null
}

// A zone on the screen: whole pixels, with `gapsIn` between neighbours and
// none at the usable area's edge.
function zoneRect(zone, area, gapsIn) {
  var g = Math.max(0, Number(gapsIn) || 0)
  var eps = 1e-6
  var x0 = area.x + zone[0] * area.width
  var y0 = area.y + zone[1] * area.height
  var x1 = area.x + (zone[0] + zone[2]) * area.width
  var y1 = area.y + (zone[1] + zone[3]) * area.height
  if (zone[0] > eps) x0 += g / 2
  if (zone[1] > eps) y0 += g / 2
  if (zone[0] + zone[2] < 1 - eps) x1 -= g / 2
  if (zone[1] + zone[3] < 1 - eps) y1 -= g / 2
  // Round the edges, not the size, so neighbours meet exactly.
  var l = Math.round(x0), t = Math.round(y0), r = Math.round(x1), b = Math.round(y1)
  return { x: l, y: t, width: r - l, height: b - t }
}

// All zones in picker order, for the arrow keys: [layoutIndex, zoneIndex].
function zoneOrder() {
  var out = []
  for (var l = 0; l < LAYOUTS.length; l++)
    for (var z = 0; z < LAYOUTS[l].zones.length; z++) out.push([l, z])
  return out
}

// ---------------------------------------------------------------- commands

function whole(n) {
  var v = Math.round(Number(n))
  return isFinite(v) ? v : null
}

function windowRef(address) {
  return '"address:' + address + '"'
}

function focusWindow(address) {
  if (!validAddress(address)) return null
  return "hl.dsp.focus({ window = " + windowRef(address) + " })"
}

function focusWorkspace(id) {
  if (!validWorkspace(id)) return null
  return 'hl.dsp.focus({ workspace = "' + id + '" })'
}

function moveToWorkspace(address, id, follow) {
  if (!validAddress(address) || !validWorkspace(id)) return null
  return 'hl.dsp.window.move({ workspace = "' + id + '", follow = ' + (follow ? "true" : "false")
    + ", window = " + windowRef(address) + " })"
}

function closeWindow(address) {
  if (!validAddress(address)) return null
  return "hl.dsp.window.close({ window = " + windowRef(address) + " })"
}

function untag(address, workspace) {
  if (!validAddress(address) || !validWorkspace(workspace)) return null
  return 'hl.dsp.window.tag({ tag = "-omarchy-minimized-from-' + workspace + '", window = ' + windowRef(address) + " })"
}

// What bringing a window forward takes: a minimized one comes back to the
// workspace it left (or the one showing) first.
function activate(win, currentWorkspace) {
  if (!win || !validAddress(win.address)) return []
  var out = []
  if (win.minimized) {
    var target = validWorkspace(win.workspace) ? win.workspace : currentWorkspace
    if (!validWorkspace(target)) return []
    out.push(moveToWorkspace(win.address, target, true))
    if (validWorkspace(win.workspace)) out.push(untag(win.address, win.workspace))
  }
  out.push(focusWindow(win.address))
  return out
}

// Put a window in a zone: float it, size it, place it, raise it.
function snap(address, rect) {
  if (!validAddress(address) || !rect) return []
  var x = whole(rect.x), y = whole(rect.y), w = whole(rect.width), h = whole(rect.height)
  if (x === null || y === null || w === null || h === null || w < 1 || h < 1) return []
  var ref = windowRef(address)
  return [
    "hl.dsp.window.float({ action = \"on\", window = " + ref + " })",
    "hl.dsp.window.resize({ x = " + w + ", y = " + h + ", window = " + ref + " })",
    "hl.dsp.window.move({ x = " + x + ", y = " + y + ", window = " + ref + " })",
    "hl.dsp.window.alter_zorder({ mode = \"top\", window = " + ref + " })"
  ]
}

function tile(address) {
  if (!validAddress(address)) return []
  return ["hl.dsp.window.float({ action = \"off\", window = " + windowRef(address) + " })"]
}

// ---------------------------------------------------------------- quick

// Quick settings' power profile button steps through what's offered.
function nextProfile(current, profiles) {
  if (!Array.isArray(profiles) || profiles.length === 0) return null
  var i = profiles.indexOf(current)
  return profiles[(i + 1) % profiles.length]
}

function clampPercent(v) {
  var n = Math.round(Number(v))
  if (!isFinite(n)) return null
  return Math.max(1, Math.min(100, n))
}

// One row per address from the `addresses` list (`fathom-desk settings`,
// `fathom-deck status`): { name, kind, address, first }, IPv4 before IPv6,
// `first` on an interface's first row, at most `max` rows in all. The same
// helper is in the other plugin; keep the two alike.
function addressRows(list, max) {
  var rows = []
  var cap = Math.max(0, Number(max) || 0)
  if (!Array.isArray(list)) return rows
  for (var i = 0; i < list.length && rows.length < cap; i++) {
    var iface = list[i]
    if (!iface || typeof iface.name !== "string" || iface.name === "") continue
    var addrs = [].concat(Array.isArray(iface.ipv4) ? iface.ipv4 : [], Array.isArray(iface.ipv6) ? iface.ipv6 : [])
    var first = true
    for (var j = 0; j < addrs.length && rows.length < cap; j++) {
      if (typeof addrs[j] !== "string" || addrs[j] === "") continue
      rows.push({ name: iface.name, kind: String(iface.kind || "other"), address: addrs[j], first: first })
      first = false
    }
  }
  return rows
}

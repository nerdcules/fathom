.pragma library

// Formatting and classification for the Command Deck. No QML imports, so the
// tests can load it with node.

function bytes(n, fmt) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) v = 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
  var decimals = (i === 0 || v >= 100) ? 0 : 1
  return (fmt ? fmt(v, decimals) : v.toFixed(decimals)) + " " + units[i]
}

function percent(used, total) {
  var u = Number(used), t = Number(total)
  if (!isFinite(u) || !isFinite(t) || t <= 0) return 0
  return Math.max(0, Math.min(100, u * 100 / t))
}

// "ok" below 85 %, "warn" to 95 %, "bad" above.
function level(pct) {
  if (pct >= 95) return "bad"
  if (pct >= 85) return "warn"
  return "ok"
}

// Docker's status text ("Up 3 days (unhealthy)", "Exited (1) 2 hours ago")
// and state, reduced to how a row should look.
function containerHealth(c) {
  if (!c) return "stopped"
  var state = String(c.state || "")
  var status = String(c.status || "")
  if (status.indexOf("(unhealthy)") !== -1) return "bad"
  if (state === "restarting") return "warn"
  if (state === "running") return status.indexOf("(health: starting)") !== -1 ? "warn" : "ok"
  if (state === "exited" && !/^Exited \(0\)/.test(status)) return "bad"
  return "stopped"
}

// "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp" -> ":8080". Host ports only,
// each once.
function hostPorts(ports) {
  var seen = {}
  var out = []
  var re = /:(\d+)->/g
  var m
  var text = String(ports || "")
  while ((m = re.exec(text)) !== null) {
    if (!seen[m[1]]) { seen[m[1]] = true; out.push(":" + m[1]) }
  }
  return out.slice(0, 3).join(" ")
}

// Containers grouped by compose project, standalone ones last.
function groupContainers(list) {
  var groups = []
  var byName = {}
  var items = Array.isArray(list) ? list : []
  for (var i = 0; i < items.length; i++) {
    var c = items[i]
    var key = String(c.project || "")
    if (!byName[key]) {
      byName[key] = { project: key, containers: [] }
      groups.push(byName[key])
    }
    byName[key].containers.push(c)
  }
  groups.sort(function(a, b) {
    if (a.project === "" && b.project !== "") return 1
    if (b.project === "" && a.project !== "") return -1
    return a.project < b.project ? -1 : (a.project > b.project ? 1 : 0)
  })
  return groups
}

function countRunning(list) {
  var n = 0
  var items = Array.isArray(list) ? list : []
  for (var i = 0; i < items.length; i++) if (items[i].state === "running") n++
  return n
}

function byKind(list, kind) {
  var out = []
  var items = Array.isArray(list) ? list : []
  for (var i = 0; i < items.length; i++) if (items[i].kind === kind) out.push(items[i])
  return out
}

function sum(list, field) {
  var t = 0
  var items = Array.isArray(list) ? list : []
  for (var i = 0; i < items.length; i++) t += Number(items[i][field]) || 0
  return t
}

// An agent is "working" while it uses noticeable CPU.
function agentBusy(a) {
  return !!a && Number(a.cpu) >= 3
}

function uptime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  return { days: d, hours: h, minutes: m }
}

// Docker's reclaimable text, "6.462GB (31%)" -> "6.462GB". Anything that
// isn't a size comes back empty.
function reclaimable(text) {
  var m = /^([0-9.]+\s*[kKMGT]?i?B)/.exec(String(text || ""))
  return m ? m[1] : ""
}

// Docker's own space use, as {images, cache, reclaim} strings.
function dockerSpace(rows) {
  var out = { images: "", cache: "", volumes: "", reclaim: [] }
  var items = Array.isArray(rows) ? rows : []
  for (var i = 0; i < items.length; i++) {
    var r = items[i]
    if (r.type === "Images") out.images = String(r.size || "")
    else if (r.type === "Build Cache") out.cache = String(r.size || "")
    else if (r.type === "Local Volumes") out.volumes = String(r.size || "")
  }
  return out
}

// Container names as docker allows them. The deck only acts on these.
function validContainerName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(String(name || ""))
}

.pragma library

// Fathom's Display dropdown (#14): the parts that are only arithmetic, so
// Node can test them (tests/bar.test.mjs). The scale arithmetic is
// Omarchy's (shell/plugins/panels/monitor/Model.js, MIT), copied so the
// dropdown offers the same scales Omarchy's does; the rest is Fathom's.

// Omarchy's scale presets and text-size stops (monitor/Panel.qml).
var SCALES = ["1", "1.25", "1.6", "2", "3", "4"]
var TEXT_STOPS = [9, 10, 11, 12, 14, 16, 20]

function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

// The scale Hyprland will really use for a mode: one that divides it evenly.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""
  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

// The presets that come out different on this mode, each the one nearest
// what it gives.
function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []
  var byEffective = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))
    if (!isFinite(requested) || !isFinite(effective)) continue
    var key = normalizeScale(effective)
    var existing = byEffective[key]
    if (!existing || Math.abs(requested - effective) < existing.distance)
      byEffective[key] = { value: String(scales[i]), index: i, distance: Math.abs(requested - effective) }
  }
  return Object.keys(byEffective)
    .map(function(key) { return byEffective[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(c) { return c.value })
}

// Which of the offered scales is the one in use, or -1.
function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1
  var best = -1
  var bestDistance = Infinity
  var normalized = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalized) continue
    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) { best = i; bestDistance = distance }
  }
  return best
}

// `omarchy-monitor-state`, one value a line: brightness (a number, or
// "unavailable" / nothing without a backlight), the internal display, the
// external one, the internal one if it's on, what's mirrored, the focused
// display, its scale, and every display as JSON.
function parseState(text) {
  var lines = String(text || "").split("\n")
  var raw = String(lines[0] || "").trim()
  var level = parseInt(raw, 10)
  var displays = []
  try { displays = JSON.parse(String(lines[7] || "[]").trim()) } catch (e) { displays = [] }
  if (!Array.isArray(displays)) displays = []
  displays = displays.filter(function(d) { return d && typeof d.name === "string" && d.name !== "" })
  return {
    brightness: raw === "" || raw === "unavailable" || !isFinite(level) ? -1 : Math.max(0, Math.min(100, level)),
    focused: String(lines[5] || "").trim(),
    scale: normalizeScale(String(lines[6] || "").trim()),
    displays: displays
  }
}

function focusedDisplay(displays, name) {
  var list = Array.isArray(displays) ? displays : []
  for (var i = 0; i < list.length; i++) if (list[i].focused) return list[i]
  for (var j = 0; j < list.length; j++) if (list[j].name === name) return list[j]
  return list.length > 0 ? list[0] : null
}

// The text-size stop nearest a font size.
function nearestStop(px) {
  var best = 0
  for (var i = 1; i < TEXT_STOPS.length; i++)
    if (Math.abs(TEXT_STOPS[i] - px) < Math.abs(TEXT_STOPS[best] - px)) best = i
  return best
}

// One row a display: lit when on. The only display that's on can't be
// turned off from here, as in Omarchy's (it would leave no screen).
function displayRows(displays) {
  var list = Array.isArray(displays) ? displays : []
  var on = list.filter(function(d) { return d.enabled }).length
  return list.map(function(d) {
    var size = Number(d.width) > 0 && Number(d.height) > 0 ? d.width + "×" + d.height : ""
    return {
      key: d.name,
      name: d.name,
      size: size,
      enabled: !!d.enabled,
      focused: !!d.focused,
      canToggle: !(d.enabled && on <= 1)
    }
  })
}

function g(cp) { return String.fromCodePoint(cp) }

// The dropdown, as the kit's factory draws it (kit/DropSections.qml). `v`:
// brightness (percent, -1 for none), textIndex, scales, scaleIndex,
// displays (displayRows), and the display's width and height, so each scale
// is labelled with what the screen really gets, as Omarchy's are (3 is 3.2×
// on 1280×800). `t` turns a string key into words.
function sections(v, t) {
  var stops = TEXT_STOPS.length - 1
  var rows = Array.isArray(v.displays) ? v.displays : []
  var px = TEXT_STOPS[Math.max(0, Math.min(stops, v.textIndex))]
  return [
    { type: "slider", key: "brightness", hidden: !(v.brightness >= 0), glyph: g(0xF00E0), tip: t("display.brightness"),
      value: Math.max(0, v.brightness) / 100, label: Math.max(0, v.brightness) + "%" },
    { type: "slider", key: "textSize", glyph: g(0xF027F), tip: t("display.textSize"), steps: stops,
      value: Math.max(0, Math.min(stops, v.textIndex)) / stops, label: t("display.px").replace("%1", px) },
    { type: "choices", key: "scale", title: t("display.scale"), hidden: !(v.scales && v.scales.length),
      options: (v.scales || []).map(function(s) {
        return { value: String(s), label: (cleanScale(s, v.width, v.height) || normalizeScale(s)) + "×" }
      }),
      chosen: v.scaleIndex >= 0 && v.scales ? String(v.scales[v.scaleIndex]) : "" },
    { type: "rows", key: "displays", title: t("display.displays"), hidden: rows.length < 2,
      rows: rows.map(function(d) {
        return { key: d.name, glyph: g(0xF0379), name: d.name,
                 detail: [d.size, d.focused ? t("display.inUse") : ""].filter(function(s) { return s !== "" }).join(" · "),
                 trail: d.enabled ? t("drop.on") : t("drop.off"), active: d.enabled, clickable: d.canToggle }
      }) }
  ]
}

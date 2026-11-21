.pragma library

// Fathom's keyboard layout dropdown (#14): what it shows, as the kit's
// factory draws it. The keyboards are read as Omarchy's widget reads them
// (KeyboardLayout.qml, KeyboardLayoutModel.js); this lists the layouts to
// pick from. Node tests: tests/bar.test.mjs.

// xkbcli's layout list -> { "gb": "English (UK)", "us(intl)": "English
// (US, intl., with dead keys)" }.
function layoutNames(text) {
  var out = {}
  var inLayouts = false
  var layout = "", variant = ""
  String(text || "").split("\n").forEach(function(line) {
    if (/^[A-Za-z_]+:/.test(line)) { inLayouts = line.indexOf("layouts:") === 0; return }
    if (!inLayouts) return
    var m = line.match(/^- layout: '([^']*)'/)
    if (m) { layout = m[1]; variant = ""; return }
    m = line.match(/^  variant: '([^']*)'/)
    if (m) { variant = m[1]; return }
    m = line.match(/^  description: (.*)$/)
    if (m && layout !== "") out[variant !== "" ? layout + "(" + variant + ")" : layout] = m[1].replace(/^'|'$/g, "")
  })
  return out
}

// A keyboard's layouts, in its order: Hyprland gives them as two comma lists.
function layouts(keyboard, names) {
  if (!keyboard || keyboard.layout === undefined) return []
  var codes = String(keyboard.layout).split(",")
  var variants = String(keyboard.variant || "").split(",")
  return codes.map(function(code, i) {
    var c = code.trim(), v = (variants[i] || "").trim()
    var key = v !== "" ? c + "(" + v + ")" : c
    return { code: key, name: (names || {})[key] || (names || {})[c] || key }
  })
}

// `v`: layouts ([{code, name}]), index (the active one), methods (input
// methods, when more than one), method (the current one's name).
function sections(v, t) {
  var list = v.layouts || []
  return [
    { type: "rows", key: "layout", hidden: list.length < 2, rows: list.map(function(l, i) {
      return { key: String(i), glyph: String.fromCodePoint(0xF030C), name: l.name, detail: l.code, active: i === v.index }
    }) },
    { type: "text", hidden: list.length >= 2 || (v.methods || 0) > 1, text: t("kb.one"), dim: true },
    { type: "rows", key: "input", hidden: (v.methods || 0) < 2, title: t("kb.inputMethod"), rows: [
      { key: "next", glyph: String.fromCodePoint(0xF0AB6), name: v.method || "", detail: t("kb.next"), trail: "Super+I" } ] }
  ]
}

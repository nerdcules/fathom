.pragma library

// Fathom's system update dropdown (#14): what it shows, as the kit's factory
// draws it. Omarchy's own check (omarchy-update-available) says what's
// waiting, a line per update ("omarchy 4.5.0-3 -> 4.6.0-1"); Update now
// runs Omarchy's own update in a terminal, as Omarchy's button does. Node
// tests: tests/bar.test.mjs.

// omarchy-update-available's lines, as rows: what, and from which version
// to which when the line says.
function updateRows(text) {
  return String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
    .map(function(line, i) {
      var m = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)$/)
      if (m) return { key: String(i), glyph: String.fromCodePoint(0xF03D7), name: m[1], detail: m[2] + " → " + m[3], clickable: false }
      return { key: String(i), glyph: String.fromCodePoint(0xF03D7), name: line, detail: "", clickable: false }
    })
}

// `v`: available, checking, lines (the check's output).
function sections(v, t) {
  var rows = updateRows(v.lines)
  return [
    { type: "rows", key: "updates", hidden: !v.available || rows.length === 0, rows: rows },
    { type: "text", hidden: v.available, text: t(v.checking ? "su.checking" : "su.none"), dim: true },
    { type: "actions", key: "do", buttons: [
      { key: "update", label: t("su.updateNow"), glyph: String.fromCodePoint(0xF01DA), primary: true },
      { key: "check", label: t("su.check"), glyph: String.fromCodePoint(0xF0450) } ].filter(function(b) {
        return b.key !== "update" || v.available
      }) }
  ]
}

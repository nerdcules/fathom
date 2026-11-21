.pragma library

// Fathom's world clock dropdown (#14): what it shows, as the kit's factory
// draws it. The cities, their times and the search are Omarchy's Elsewhen
// model (Model.js, copied); Elsewhen.qml fetches as Elsewhen does. Node
// tests: tests/bar.test.mjs.
//
// `t(key)` gives words: Fathom's own keys, and Omarchy's for keys starting
// with "@".

var SUN = 0xF0599
var MOON = 0xF0594

// One city's row: day or night, its name, the day if it isn't today, how far
// it is from here (or from UTC), its temperature, and its time.
function cityRow(r, index, chosen, offset, temp) {
  var detail = []
  if (r.ready && r.dayLabel) detail.push(r.dayLabel)
  if (r.ready && offset) detail.push(offset)
  if (temp) detail.push(temp)
  return {
    key: String(index),
    glyph: r.ready ? String.fromCodePoint(r.daytime ? SUN : MOON) : "",
    name: String(r.label || ""),
    detail: detail.join(" · "),
    trail: r.ready ? r.time + (r.meridiem ? " " + r.meridiem : "") : "",
    strong: true,
    active: index === chosen
  }
}

// Omarchy's "+  Add a city" without its own plus: the button has a glyph.
function bare(label) { return String(label).replace(/^\+\s*/, "") }

// `v`: rows (Model.rows), offsets ([text] for each row), temps ([text]),
// chosen (a row's index, or -1), count (cities), adding, choosingHere,
// query, matches ([{label, value, region, utc}]), matchIndex, searching,
// hour24, utc (offsets from UTC), units ("C" or "F"), loading.
function sections(v, t) {
  var rows = v.rows || []
  var matches = (v.matches || []).map(function(m, i) {
    return { key: String(i), name: String(m.label || ""),
             detail: [m.region || m.value, m.utc || ""].filter(function(s) { return s !== "" }).join(" · ") }
  })
  var searching = !!(v.adding || v.choosingHere)
  return [
    { type: "rows", key: "cities", hidden: rows.length === 0,
      rows: rows.map(function(r, i) { return cityRow(r, i, v.chosen, (v.offsets || [])[i], (v.temps || [])[i]) }) },
    { type: "text", hidden: rows.length > 0, text: t(v.loading ? "@elsewhen.loadingZones" : "@elsewhen.loadingCities"), dim: true },
    { type: "actions", key: "city", hidden: v.chosen < 0 || v.chosen >= rows.length || searching, buttons: [
      { key: "up", label: t("ws.up"), glyph: String.fromCodePoint(0xF0143) },
      { key: "down", label: t("ws.down"), glyph: String.fromCodePoint(0xF0140) },
      { key: "remove", label: t("@elsewhen.remove"), glyph: String.fromCodePoint(0xF0156) } ] },
    { type: "search", key: v.choosingHere ? "here" : "add", hidden: !searching, text: v.query || "",
      placeholder: t(v.choosingHere ? "@elsewhen.whereAreYou" : "@elsewhen.searchCities"),
      results: matches, chosen: Math.min(v.matchIndex || 0, Math.max(0, matches.length - 1)) },
    { type: "text", hidden: !searching || !v.searching, text: t("@elsewhen.searchingPlaces"), dim: true },
    { type: "actions", key: "do", hidden: searching, buttons: [
      { key: "add", label: bare(t("@elsewhen.addCity")), glyph: "+", primary: true },
      { key: "here", label: t("@elsewhen.whereAreYou"), glyph: String.fromCodePoint(0xF034E) } ] },
    { type: "actions", key: "show", hidden: searching, buttons: [
      { key: "hour24", label: t("ws.hour24"), primary: !!v.hour24 },
      { key: "utc", label: t("ws.utc"), primary: !!v.utc },
      { key: "units", label: v.units === "F" ? "°F" : "°C" } ] }
  ]
}

// The card's keys while no field has the keyboard: Delete removes the
// chosen city, a adds one.
function keyAction(key, text) {
  if (key === 0x01000007 || key === 0x01000003) return "remove"   // Qt.Key_Delete, Qt.Key_Backspace
  if (text === "a" || text === "A") return "add"
  return ""
}

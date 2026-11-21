.pragma library

// Fathom's weather dropdown (#14): what it shows, as the kit's factory draws
// it. The sources, numbers and icons are Omarchy's (Model.js); Weather.qml
// fetches as Omarchy's does. Node tests: tests/bar.test.mjs.
//
// `v`: hasCurrent, feels, wind, humidity (words), location (a name, or ""
// while it's being found), editing, saving, query (the search field's text
// to start with), results ([{name, description}] from the geocoder),
// chosen, days ([{key, glyph, name, max, min}]). `t` turns a string key
// into words.
function sections(v, t) {
  var results = (v.results || []).map(function(r, i) {
    return { key: String(i), name: r.name || "", detail: r.description || "" }
  })
  var days = v.days || []
  return [
    { type: "facts", hidden: !v.hasCurrent, items: [
      { label: t("weather.feels"), value: v.feels || "" },
      { label: t("weather.wind"), value: v.wind || "" },
      { label: t("weather.humidity"), value: v.humidity || "" }
    ] },
    { type: "rows", key: "location", hidden: !!v.editing, rows: [
      { key: "location", glyph: String.fromCodePoint(0xF034E), name: v.location || t("weather.finding"),
        detail: t("weather.change") }
    ] },
    { type: "search", key: "search", hidden: !v.editing, text: v.query || "", placeholder: t("weather.searchCity"),
      busy: !!v.saving, busyLabel: t("weather.saving"), results: v.saving ? [] : results, chosen: v.chosen || 0 },
    { type: "actions", key: "searchActions", hidden: !v.editing || !!v.saving, buttons: [
      { key: "auto", label: t("weather.useMyLocation"), glyph: String.fromCodePoint(0xF01A4) },
      { key: "cancel", label: t("weather.cancel") }
    ] },
    { type: "strip", key: "days", hidden: days.length === 0, items: days.map(function(d) {
      return { key: d.key, glyph: d.glyph, name: d.name, detail: [d.max, d.min].filter(function(s) { return s !== "" }).join(" / ") }
    }) },
    { type: "text", hidden: !!v.hasCurrent, text: t("weather.fetching"), dim: true }
  ]
}

.pragma library

// Fathom's clock dropdown (#14): what it shows under the month, as the kit's
// factory draws it, and the keys it takes. The calendar arithmetic is
// Omarchy's (Model.js). Node tests: tests/bar.test.mjs.

// Under the month: how much of the year is gone; how much of a life, once a
// birth year is set (Omarchy's memento mori: double-click the year to set
// one, double-click the life bar to put it away); and while setting one, the
// two fields. `v`: year, yearDone (0..1), yearPercent, birthYear, age,
// lifeExpectancy, lifeDone, lifePercent, editing. `t` turns a string key
// into words.
function sections(v, t) {
  return [
    { type: "meter", key: "year", hidden: !!v.editing, label: String(v.year), trail: v.yearPercent + "%", value: v.yearDone },
    { type: "meter", key: "life", hidden: !!v.editing || !(v.birthYear > 0), label: t("clock.life"),
      trail: v.lifePercent + "%", value: v.lifeDone },
    { type: "fields", key: "lifeEdit", hidden: !v.editing, okLabel: t("clock.save"), cancelLabel: t("clock.cancel"),
      fields: [
        { key: "born", label: t("clock.born"), value: v.birthYear > 0 ? String(v.birthYear) : "",
          placeholder: t("clock.year"), digits: true },
        { key: "expectancy", label: t("clock.liveTo"), value: String(v.lifeExpectancy), digits: true }
      ] }
  ]
}

// What a key does in the calendar, as in Omarchy's: Left and Right (or h and
// l, [ and ]) a month, Up and Down (k and j, { and }) a year, T or Return
// back to today, W the first day of the week. Anything else: "".
function keyAction(key, text) {
  var named = {
    16777234: "month-1", 16777236: "month+1",   // Left, Right
    16777235: "year-1", 16777237: "year+1",     // Up, Down
    16777220: "today", 16777221: "today"        // Return, Enter
  }
  if (named[key]) return named[key]
  var typed = {
    "h": "month-1", "l": "month+1", "[": "month-1", "]": "month+1",
    "k": "year-1", "j": "year+1", "{": "year-1", "}": "year+1",
    "t": "today", "T": "today", "w": "weekStart", "W": "weekStart"
  }
  return typed[String(text || "")] || ""
}

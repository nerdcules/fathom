// Run with: node --test tests/
// Fathom's bar dropdowns (#14): the arithmetic each one does, and that every
// dropdown is a clone of the Omarchy item it replaces.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import vm from "node:vm";

const bar = new URL("../bar/", import.meta.url);
const read = (path) => readFileSync(new URL(path, bar), "utf8");
const load = (path, names) => {
  const o = {};
  vm.runInNewContext(read(path).replace(/^\.pragma library\s*$/m, "") +
    names.map((n) => `this.${n} = ${n};`).join(" "), o);
  return o;
};
const plain = (v) => JSON.parse(JSON.stringify(v));

const D = load("plugin/fathom.display/Display.js", ["SCALES", "TEXT_STOPS", "clampBrightness", "normalizeScale",
  "cleanScale", "availableScales", "matchingScaleIndex", "parseState", "focusedDisplay", "nearestStop", "displayRows", "sections"]);

// What `omarchy-monitor-state` printed on this laptop (20 November 2026).
const LAPTOP = '17\neDP-1\n\neDP-1\n\neDP-1\n1.3\n[{"name":"eDP-1","enabled":true,"focused":true,"width":2496,"height":1664}]\n';

test("display: the state script's lines", () => {
  const s = D.parseState(LAPTOP);
  assert.equal(s.brightness, 17);
  assert.equal(s.focused, "eDP-1");
  assert.equal(s.scale, "1.3");
  assert.deepEqual(plain(s.displays), [{ name: "eDP-1", enabled: true, focused: true, width: 2496, height: 1664 }]);
});

test("display: no backlight is no brightness, and junk is no displays", () => {
  assert.equal(D.parseState("unavailable\n").brightness, -1);
  assert.equal(D.parseState("").brightness, -1);
  assert.equal(D.parseState("x\n\n\n\n\n\n\nnot json").brightness, -1);
  assert.deepEqual(plain(D.parseState("x\n\n\n\n\n\n\nnot json").displays), []);
  assert.deepEqual(plain(D.parseState('5\n\n\n\n\n\n\n[{"enabled":true},null,{"name":"DP-1"}]').displays), [{ name: "DP-1" }]);
  assert.equal(D.parseState("250\n").brightness, 100);
});

test("display: brightness stays from 1 to 100", () => {
  assert.equal(D.clampBrightness(0), 1);
  assert.equal(D.clampBrightness(140), 100);
  assert.equal(D.clampBrightness("45.4"), 45);
  assert.equal(D.clampBrightness("x"), 1);
});

test("display: the scales offered are Omarchy's, as this mode gives them", () => {
  // 2496x1664: 1.25 isn't a clean scale and becomes 1.3, which is in use here.
  const scales = D.availableScales(D.SCALES, 2496, 1664);
  assert.deepEqual(plain(scales), ["1", "1.25", "1.6", "2", "3", "4"]);
  assert.equal(D.cleanScale("1.25", 2496, 1664), "1.3");
  assert.equal(D.matchingScaleIndex(scales, "1.3", 2496, 1664), 1);
  assert.equal(D.matchingScaleIndex(scales, "5", 2496, 1664), -1);
  // Without a mode, every preset.
  assert.deepEqual(plain(D.availableScales(D.SCALES, 0, 0)), plain(D.SCALES));
});

test("display: text size snaps to the nearest stop", () => {
  assert.deepEqual(plain(D.TEXT_STOPS), [9, 10, 11, 12, 14, 16, 20]);
  assert.equal(D.nearestStop(14), 4);
  assert.equal(D.nearestStop(13.2), 4);
  assert.equal(D.nearestStop(30), 6);
  assert.equal(D.nearestStop(1), 0);
});

test("display: one row a display, and the last one on stays on", () => {
  const rows = D.displayRows([
    { name: "eDP-1", enabled: true, focused: true, width: 2496, height: 1664 },
    { name: "HDMI-A-1", enabled: false, focused: false, width: 1920, height: 1080 },
  ]);
  assert.deepEqual(plain(rows), [
    { key: "eDP-1", name: "eDP-1", size: "2496×1664", enabled: true, focused: true, canToggle: false },
    { key: "HDMI-A-1", name: "HDMI-A-1", size: "1920×1080", enabled: false, focused: false, canToggle: true },
  ]);
  const two = D.displayRows([{ name: "a", enabled: true }, { name: "b", enabled: true }]);
  assert.deepEqual(two.map((r) => r.canToggle), [true, true]);
  assert.equal(D.focusedDisplay([{ name: "a" }, { name: "b", focused: true }], "").name, "b");
  assert.equal(D.focusedDisplay([{ name: "a" }, { name: "b" }], "b").name, "b");
  assert.equal(D.focusedDisplay([], "b"), null);
});

test("display: the dropdown's description", () => {
  const t = (k) => `[${k}]`;
  const rows = D.displayRows([
    { name: "eDP-1", enabled: true, focused: true, width: 2496, height: 1664 },
    { name: "HDMI-A-1", enabled: true, focused: false, width: 1920, height: 1080 },
  ]);
  const s = plain(D.sections({ brightness: 17, textIndex: 4, scales: ["1", "1.25", "2"], scaleIndex: 1, displays: rows,
    width: 2496, height: 1664 }, t));
  assert.deepEqual(s.map((x) => [x.type, x.key, !!x.hidden]),
    [["slider", "brightness", false], ["slider", "textSize", false], ["choices", "scale", false], ["rows", "displays", false]]);
  assert.equal(s[0].value, 0.17);
  assert.equal(s[0].label, "17%");
  assert.equal(s[1].steps, 6);
  assert.equal(s[1].value, 4 / 6);
  assert.equal(s[1].label, "[display.px]".replace("%1", 14));
  assert.equal(s[2].chosen, "1.25");
  // Labelled with what this mode really gets: 1.25 is 1.3 on 2496×1664.
  assert.deepEqual(s[2].options.map((o) => o.label), ["1×", "1.3×", "2×"]);
  assert.deepEqual(s[2].options.map((o) => o.value), ["1", "1.25", "2"]);
  // As Omarchy's labels them on the test VM's 1280×800: 3 is 3.2.
  const vm = plain(D.sections({ brightness: -1, textIndex: 3, scales: D.availableScales(D.SCALES, 1280, 800),
    scaleIndex: 0, displays: [], width: 1280, height: 800 }, t));
  assert.deepEqual(vm[2].options.map((o) => o.label), ["1×", "1.25×", "1.6×", "2×", "3.2×", "4×"]);
  assert.deepEqual(s[3].rows.map((r) => [r.key, r.detail, r.trail, r.clickable]),
    [["eDP-1", "2496×1664 · [display.inUse]", "[drop.on]", true], ["HDMI-A-1", "1920×1080", "[drop.on]", true]]);
  // No backlight, one display, no scale in use.
  const one = plain(D.sections({ brightness: -1, textIndex: 0, scales: ["1"], scaleIndex: -1, displays: rows.slice(0, 1) }, t));
  assert.equal(one[0].hidden, true);
  assert.equal(one[3].hidden, true);
  assert.equal(one[2].chosen, "");
});

// Every string a dropdown asks for is in its strings file, with the kit's own.
test("bar: each dropdown has the words it asks for", () => {
  for (const id of readdirSync(new URL("plugin/", bar))) {
    const strings = JSON.parse(read(`plugin/${id}/i18n/en.json`));
    const used = new Set(["drop.on", "drop.off"]);
    for (const file of readdirSync(new URL(`plugin/${id}/`, bar))) {
      if (!/\.(qml|js)$/.test(file)) continue;
      // Not Omarchy's own catalog (I18n.t): the clock's label keeps
      // Omarchy's tooltip, in every language Omarchy has.
      for (const m of read(`plugin/${id}/${file}`).matchAll(/(?<!I18n\.)\bt\("([a-z][\w.]*)"\)/g)) used.add(m[1]);
    }
    for (const key of used) assert.ok(key in strings, `${id}: ${key} is in i18n/en.json`);
  }
});

const C = load("plugin/fathom.clock/Calendar.js", ["sections", "keyAction"]);
const M = load("plugin/fathom.clock/Model.js", ["monthGrid", "isoWeek", "yearProgressPercent", "stepMonth",
  "normalizedWeekStart", "weekStartSettingName", "toggledWeekStart"]);

test("clock: under the month, the year; the life bar once a birth year is set", () => {
  const t = (k) => `[${k}]`;
  const v = { year: 2026, yearDone: 0.884, yearPercent: 88, birthYear: 0, age: 0, lifeExpectancy: 90,
    lifeDone: 0, lifePercent: 0, editing: false };
  let s = plain(C.sections(v, t));
  assert.deepEqual(s.map((x) => [x.type, x.key, !!x.hidden]),
    [["meter", "year", false], ["meter", "life", true], ["fields", "lifeEdit", true]]);
  assert.equal(s[0].label, "2026");
  assert.equal(s[0].trail, "88%");
  s = plain(C.sections({ ...v, birthYear: 1980, age: 46, lifeDone: 46 / 90, lifePercent: 51 }, t));
  assert.equal(s[1].hidden, false);
  assert.equal(s[1].trail, "51%");
  // Setting one: the fields, filled with what's set, and no bars.
  s = plain(C.sections({ ...v, birthYear: 1980, editing: true }, t));
  assert.deepEqual(s.map((x) => !!x.hidden), [true, true, false]);
  assert.deepEqual(s[2].fields.map((f) => [f.key, f.value, f.digits]), [["born", "1980", true], ["expectancy", "90", true]]);
  assert.equal(plain(C.sections({ ...v, editing: true }, t))[2].fields[0].value, "", "no birth year: an empty field");
});

test("clock: the keys, as Omarchy's calendar takes them", () => {
  const Key = { Left: 0x01000012, Up: 0x01000013, Right: 0x01000014, Down: 0x01000015, Return: 0x01000004, Enter: 0x01000005 };
  assert.equal(C.keyAction(Key.Left, ""), "month-1");
  assert.equal(C.keyAction(Key.Right, ""), "month+1");
  assert.equal(C.keyAction(Key.Up, ""), "year-1");
  assert.equal(C.keyAction(Key.Down, ""), "year+1");
  assert.equal(C.keyAction(Key.Return, ""), "today");
  assert.equal(C.keyAction(Key.Enter, ""), "today");
  for (const [text, act] of [["h", "month-1"], ["l", "month+1"], ["[", "month-1"], ["]", "month+1"], ["k", "year-1"],
    ["j", "year+1"], ["{", "year-1"], ["}", "year+1"], ["t", "today"], ["T", "today"], ["w", "weekStart"], ["W", "weekStart"]])
    assert.equal(C.keyAction(0x41, text), act, text);
  assert.equal(C.keyAction(0x41, "a"), "");
  assert.equal(C.keyAction(0x01000001, ""), "", "Tab is the card's");
});

test("clock: the month as the calendar draws it (Omarchy's arithmetic)", () => {
  const weeks = plain(M.monthGrid(2026, 10, 1, "2026-11-20"));
  assert.equal(weeks.length, 6);
  assert.equal(weeks[0].days[0].key, "2026-10-26");
  assert.deepEqual(weeks.map((w) => w.week), [44, 45, 46, 47, 48, 49]);
  assert.deepEqual(weeks.flatMap((w) => w.days).filter((d) => d.today).map((d) => d.key), ["2026-11-20"]);
  // Sunday first: the row starts on the Sunday before.
  assert.equal(plain(M.monthGrid(2026, 10, 0, ""))[0].days[0].key, "2026-11-01");
  assert.equal(M.isoWeek(2026, 10, 20), 47);
  assert.deepEqual(plain(M.stepMonth(2026, 11, 1)), { year: 2027, month: 0 });
  assert.deepEqual(plain(M.stepMonth(2026, 0, -12)), { year: 2025, month: 0 });
  assert.equal(M.weekStartSettingName(M.toggledWeekStart(1)), "sunday");
  assert.equal(M.normalizedWeekStart("monday", 0), 1);
});

const W = load("plugin/fathom.weather/Weather.js", ["sections"]);
const WM = load("plugin/fathom.weather/Model.js", ["openMeteoCurrentCondition", "buildForecastDays", "dayIcon",
  "bareTempForDay", "currentIcon", "formatTemp", "shouldUseImperial", "locationCommit", "parseGeocodingResults"]);

// The shape open-meteo answers the dropdown's request with (made up values).
const METEO = {
  current: { temperature_2m: 7.4, apparent_temperature: 4.9, relative_humidity_2m: 81, wind_speed_10m: 13.2, weather_code: 3, is_day: 1 },
  daily: { time: ["2026-11-21", "2026-11-22", "2026-11-23", "2026-11-24"], weather_code: [3, 61, 0, 2],
    temperature_2m_max: [8.2, 9.6, 6.1, 7], temperature_2m_min: [3.1, 5.4, 0.2, 1] },
};

test("weather: what the dropdown shows, from Omarchy's model", () => {
  const t = (k) => `[${k}]`;
  const current = WM.openMeteoCurrentCondition(METEO);
  assert.ok(current, "a current condition from open-meteo");
  const days = WM.buildForecastDays(null, METEO, "2026-11-21").map((d) => ({
    key: d.date, glyph: WM.dayIcon(d), name: d.date,
    max: WM.bareTempForDay(d, "max", false, String), min: WM.bareTempForDay(d, "min", false, String),
  }));
  assert.ok(days.length >= 1 && days.every((d) => d.key > "2026-11-21"), "the coming days, not today");
  const s = plain(W.sections({ hasCurrent: true, feels: "5°C", wind: "13 km/h", humidity: "81%", location: "Leeds",
    editing: false, saving: false, query: "", results: [], chosen: 0, days }, t));
  assert.deepEqual(s.map((x) => [x.type, !!x.hidden]),
    [["facts", false], ["rows", false], ["search", true], ["actions", true], ["strip", false], ["text", true]]);
  assert.deepEqual(s[0].items.map((i) => i.value), ["5°C", "13 km/h", "81%"]);
  assert.equal(s[1].rows[0].name, "Leeds");
  assert.ok(s[4].items.every((i) => /°/.test(i.detail) && i.glyph !== ""), "each day: an icon and its high / low");
});

test("weather: changing the place, and before anything is fetched", () => {
  const t = (k) => `[${k}]`;
  const results = WM.parseGeocodingResults(JSON.stringify({ results: [
    { name: "London", admin1: "England", country: "United Kingdom", latitude: 51.5, longitude: -0.12 },
    { name: "London", admin1: "Ontario", country: "Canada", latitude: 42.98, longitude: -81.23 } ] }));
  let s = plain(W.sections({ hasCurrent: false, location: "", editing: true, saving: false, query: "Lon",
    results, chosen: 1, days: [] }, t));
  assert.deepEqual(s.map((x) => !!x.hidden), [true, true, false, false, true, false]);
  assert.deepEqual(s[2].results.map((r) => [r.key, r.name, r.detail]),
    [["0", "London", plain(results)[0].description], ["1", "London", plain(results)[1].description]]);
  assert.equal(s[2].chosen, 1);
  assert.equal(s[2].text, "Lon");
  // Picking one: the field waits, no results or buttons, until it loads.
  s = plain(W.sections({ hasCurrent: true, editing: true, saving: true, results, days: [] }, t));
  assert.equal(s[2].busy, true);
  assert.deepEqual(s[2].results, []);
  assert.equal(s[3].hidden, true);
  // Nothing found yet: the place says it's being found.
  assert.equal(plain(W.sections({ hasCurrent: false, location: "", days: [] }, t))[1].rows[0].name, "[weather.finding]");
  // Return in the field takes the chosen result, as Omarchy's does.
  assert.equal(plain(WM.locationCommit("Lon", results, 1)).latitude, 42.98);
});

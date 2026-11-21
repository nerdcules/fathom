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

// Tailscale: Fathom's dropdown over Omarchy's own model (copied unchanged).
const TS = load("plugin/fathom.tailscale/Tailscale.js", ["sections", "keyAction", "filterPeers", "fill", "MACHINE_LIMIT"]);
const TM = load("plugin/fathom.tailscale/Model.js", ["parseStatus", "osIcon"]);
const tsWords = { "@tailscale.machinesCount": "MACHINES · %1", "@tailscale.machinesFiltered": "MACHINES · %1 OF %2",
  "ts.more": "Showing %1 of %2", "ts.copied": "Copied %1" };
const tt = (k) => tsWords[k] || `[${k}]`;
const tsStatus = TM.parseStatus(JSON.stringify({
  BackendState: "Running",
  Self: { HostName: "laptop", DNSName: "laptop.tail.ts.net.", TailscaleIPs: ["100.64.0.1"], UserID: 1 },
  Peer: {
    k1: { HostName: "pc", DNSName: "pc.tail.ts.net.", TailscaleIPs: ["100.64.0.2", "fd7a:115c:a1e0::2"], Online: true, OS: "windows" },
    k2: { HostName: "nas", DNSName: "nas.tail.ts.net.", TailscaleIPs: ["100.64.0.3"], Online: true, OS: "linux", ExitNodeOption: true, ExitNode: true }
  }
}), (s) => s);
const tsView = (more) => Object.assign({
  installed: true, active: true, status: "Connected", peersLoaded: true, peers: tsStatus.peers,
  exitNodes: tsStatus.exitNodes.concat([{ id: "mullvad:add", AddMullvad: true }]), accounts: [], osIcon: TM.osIcon
}, more || {});
const shownTypes = (s) => plain(s).filter((x) => !x.hidden).map((x) => x.type + (x.key ? ":" + x.key : ""));

test("tailscale: on, with its machines, exit nodes and what can be copied", () => {
  const s = plain(TS.sections(tsView({ chosenPeer: tsStatus.peers[1], canSend: true }), tt));
  assert.deepEqual(shownTypes(s), ["switch:power", "rows:exit", "search:machines", "actions:peer"]);
  const machines = s.find((x) => x.key === "machines");
  assert.equal(machines.placeholder, "MACHINES · 2");
  assert.deepEqual(machines.results.map((r) => [r.name, r.detail]), [["nas", "100.64.0.3 · linux"], ["pc", "100.64.0.2 · windows"]]);
  assert.equal(machines.results[1].glyph, TM.osIcon("windows"));
  const exit = s.find((x) => x.key === "exit").rows;
  assert.deepEqual(exit.map((r) => [r.name, !!r.active]), [["nas", true], ["[@tailscale.chooseMullvadRegion]", false]]);
  assert.deepEqual(s.find((x) => x.key === "peer").buttons.map((b) => b.key), ["ip", "name", "dns", "ipv6", "send"]);
});

test("tailscale: searching narrows the machines and says how many", () => {
  const s = plain(TS.sections(tsView({ query: "PC" }), tt));
  const machines = s.find((x) => x.key === "machines");
  assert.deepEqual(machines.results.map((r) => r.name), ["pc"]);
  assert.equal(machines.placeholder, "MACHINES · 1 OF 2");
  const none = plain(TS.sections(tsView({ query: "zzz" }), tt));
  assert.ok(shownTypes(none).includes("text"), "no matching machines says so");
  assert.equal(none.filter((x) => !x.hidden && x.type === "text")[0].text, "[@tailscale.noMatchingMachines]");
});

test("tailscale: a big tailnet draws the first machines and says there are more", () => {
  const many = Array.from({ length: 45 }, (_, i) => ({ id: "p" + i, DisplayName: "m" + i, TailscaleIPs: ["100.64.1." + i], Online: true }));
  const s = plain(TS.sections(tsView({ peers: many }), tt));
  assert.equal(s.find((x) => x.key === "machines").results.length, TS.MACHINE_LIMIT);
  assert.ok(s.some((x) => !x.hidden && x.text === "Showing 40 of 45"));
});

test("tailscale: off, logged out and not installed", () => {
  assert.deepEqual(shownTypes(TS.sections(tsView({ active: false, status: "Disconnected" }), tt)), ["switch:power"]);
  assert.deepEqual(shownTypes(TS.sections({ installed: false }, tt)), ["text"]);
  const accounts = plain(TS.sections(tsView({ showAccounts: true, operatorDenied: true, accountId: "a1",
    accounts: [{ id: "a1", label: "home" }, { id: "a2", label: "work" }] }), tt)).find((x) => x.key === "account").rows;
  assert.deepEqual(accounts.map((r) => [r.key, !!r.active]), [["@operator", false], ["a1", true], ["a2", false]]);
  assert.deepEqual(["t", "r", "c", "n", "d", "s", "/", "x"].map((c) => TS.keyAction(0, c)), ["toggle", "refresh", "ip", "name", "dns", "send", "search", ""]);
  assert.equal(TS.fill("%1 of %2", 3, 9), "3 of 9");
});

// Agents: Fathom's dropdown over the records Omarchy's Main.qml reads.
const AG = load("plugin/fathom.agents/Agents.js", ["sections", "displayWindows", "bindingWindow", "formatDuration",
  "usageNote", "needsSignIn", "summaryPhrases", "alarming", "fill", "starterPrompt"]);
const agWords = { "@agents.durationDaysHours": "%1d %2h", "@agents.durationHoursMinutes": "%1h %2m", "@agents.durationMinutes": "%1m",
  "@agents.windowSession": "Session", "@agents.windowWeekly": "Weekly", "@agents.balanceSpent": "%1 spent of %2 funded",
  "@agents.switchAutoAt": "Switch here automatically at %1%", "@agents.mostlyModel": "Mostly %1" };
const at = (k) => agWords[k] || `[${k}]`;
const atn = (k, n) => `[${k} ${n}]`;
const anum = (n, d) => d ? Number(n).toFixed(d) : String(n);
const agNow = Date.parse("2026-11-21T12:00:00Z");
const claude = { providerId: "claude", providerName: "Claude Code", tierLabel: "max", usageStatusText: "", limits: [
  { label: "Session (5-hour)", percent: 0.03, resetsAt: "2026-11-21T14:30:00Z" },
  { label: "Weekly (7-day)", percent: 0.92, resetsAt: "2026-11-25T13:00:00Z" },
  { label: "Fable Weekly", title: "Fable Weekly", percent: 0.23, resetsAt: "2026-11-25T13:00:00Z" } ] };

test("agents: limits as meters, a model's own allowance on its window, the alarm from 90%", () => {
  const s = plain(AG.sections({ providers: [claude], now: agNow, iconFor: (id) => "file:///x/" + id + ".svg" }, at, atn, anum));
  assert.deepEqual(s[0], { type: "heading", key: "agent claude", icon: "file:///x/claude.svg", glyph: String.fromCodePoint(0xF16A3),
    text: "Claude Code", detail: "Max" });
  const meters = s.filter((x) => x.type === "meter");
  assert.deepEqual(meters.map((m) => [m.label, m.trail, m.alarm]), [
    ["Session", "3% · 2h 30m", false], ["Weekly · Fable 23%", "92% · 4d 1h", true]]);
  assert.equal(AG.alarming([claude], agNow), true);
  assert.equal(AG.alarming([claude], Date.parse("2026-11-26T00:00:00Z")), false, "a window past its reset is empty");
});

test("agents: a lapsed sign-in, a stale note, accounts and a balance", () => {
  const lapsed = Object.assign({}, claude, { usageStatusText: "Sign-in expired" });
  assert.equal(AG.needsSignIn(lapsed), true);
  assert.equal(AG.needsSignIn(Object.assign({}, lapsed, { providerId: "cursor" })), false, "only the agents Omarchy signs in");
  assert.equal(AG.usageNote(Object.assign({}, claude, { limitsStale: true, authHelpText: "Run `codex login` to authenticate." }), at),
    "[@agents.helpRunToAuthenticate]");
  const s = plain(AG.sections({ providers: [lapsed, {
    providerId: "codex", providerName: "Codex", tierLabel: "", accountSwitch: { mode: "auto", threshold: 90 },
    accounts: [{ id: "a", label: "Home", active: true, limits: [{ label: "5h window", percent: 0.5 }] },
               { id: "b", label: "Work", active: false, plan: "Pro", limits: [] }] }, {
    providerId: "openrouter", providerName: "OpenRouter", tierLabel: "Prepaid",
    balance: { remaining: 4, funded: 50, spent: 46, currency: "USD", estimated: false } }], now: agNow }, at, atn, anum));
  assert.deepEqual(s.find((x) => x.key === "signin").buttons.map((b) => b.key), ["claude"]);
  const rows = s.filter((x) => x.key === "account codex").map((x) => x.rows[0]);
  assert.deepEqual(rows.map((r) => [r.name, r.active, r.clickable, r.detail]), [["Home", true, false, ""], ["Work", false, true, "Pro"]]);
  const sw = s.find((x) => x.key === "autoswitch codex");
  assert.deepEqual([sw.on, sw.detail], [true, "Switch here automatically at 90%"]);
  const bal = s.find((x) => x.key === "balance openrouter");
  assert.deepEqual([bal.trail, bal.value, bal.alarm], ["$4.00", 0.08, true]);
  assert.ok(s.some((x) => x.text === "$46.00 spent of $50.00 funded"));
});

test("agents: no agents yet, the actions, starters and the summary line", () => {
  const s = plain(AG.sections({ providers: [], now: agNow, adding: true }, at, atn, anum));
  assert.equal(s[0].text, "[@agents.signInIntro]");
  assert.deepEqual(s.find((x) => x.key === "add").buttons.map((b) => b.key), ["claude", "codex", "grok"]);
  assert.equal(s.find((x) => x.key === "add").hidden, false);
  assert.deepEqual(s.find((x) => x.key === "starter").rows.map((r) => r.key), ["theme", "plugin", "app"]);
  assert.match(AG.starterPrompt("app"), /omarchy-app skill/);
  const phrases = AG.summaryPhrases([{ recentDays: [{ date: "2026-11-20", messageCount: 900 }], todayTotalTokens: 100,
    todayPrompts: 3, modelUsage: { m1: { inputTokens: 5, outputTokens: 5 } } }], atn, at, anum, () => "Opus", (n) => n + " tok", () => "Friday");
  assert.deepEqual(plain(phrases), ["[@agents.tokensThisWeek 900]", "[@agents.tokensToday 100]", "Mostly Opus", "[@agents.busiestDay]", "[@agents.promptsToday 3]"]);
});

// World clock: Fathom's dropdown over Elsewhen's own model (copied unchanged).
const WS = load("plugin/fathom.elsewhen/Elsewhen.js", ["sections", "cityRow", "keyAction"]);
const EM = load("plugin/fathom.elsewhen/Model.js", ["rows", "parseCities", "utcOffsetLabel", "searchZones", "zoneOptions"]);
const wst = (k) => `[${k}]`;
// 23:30 UTC: 23:30 in London, 00:30 the next day in Paris, 08:30 next day in Tokyo, 15:30 in Los Angeles.
const wsNow = Date.parse("2026-11-21T23:30:00Z");
const wsZones = EM.parseCities([{ name: "London", zone: "Europe/London" }, { name: "Paris", zone: "Europe/Paris" },
  { name: "Tokyo", zone: "Asia/Tokyo" }, { name: "Los Angeles", zone: "America/Los_Angeles" }], "");
// Elsewhen counts "Tomorrow" from this machine's own day; the tests read it in UTC.
const wsRows = (hour24) => {
  const tz = process.env.TZ;
  process.env.TZ = "UTC";
  try { return plain(EM.rows(wsZones, wsProbe, wsNow, 0, hour24, null)); }
  finally { if (tz === undefined) delete process.env.TZ; else process.env.TZ = tz; }
};
const wsProbe = { "Europe/London": { offsetMinutes: 0, abbr: "GMT" }, "Europe/Paris": { offsetMinutes: 60, abbr: "CET" },
  "Asia/Tokyo": { offsetMinutes: 540, abbr: "JST" }, "America/Los_Angeles": { offsetMinutes: -480, abbr: "PST" } };

test("world clock: a row per city with its time, day, distance and temperature", () => {
  const rows = wsRows(true);
  const s = plain(WS.sections({ rows, offsets: rows.map((r) => r.relative), temps: ["9°C", "", "", ""], chosen: -1 }, wst));
  const cities = s.find((x) => x.key === "cities").rows;
  assert.deepEqual(cities.map((r) => [r.name, r.trail, r.detail]), [
    ["London", "23:30", "9°C"], ["Paris", "00:30", "Tomorrow · +1h"], ["Tokyo", "08:30", "Tomorrow · +9h"], ["Los Angeles", "15:30", "-8h"]]);
  assert.deepEqual(cities.map((r) => r.glyph === String.fromCodePoint(0xF0599)), [false, false, true, true], "day or night");
  assert.ok(cities.every((r) => r.strong), "the time is the row's point");
  assert.equal(s.find((x) => x.key === "city").hidden, true, "no city chosen, no city actions");
  assert.equal(EM.utcOffsetLabel(-480, null), "UTC-8");
});

test("world clock: a chosen city, the searches, and the keys", () => {
  const rows = wsRows(false);
  assert.equal(WS.cityRow(rows[2], 2, 2, "", "").trail, "8:30 AM", "12-hour time with its AM or PM");
  const chosen = plain(WS.sections({ rows, chosen: 1 }, wst));
  assert.equal(chosen.find((x) => x.key === "city").hidden, false);
  assert.equal(chosen.find((x) => x.key === "cities").rows[1].active, true);
  const adding = plain(WS.sections({ rows, chosen: -1, adding: true, query: "san", searching: true,
    matches: [{ label: "San Francisco", value: "America/Los_Angeles", region: "California, US", utc: "UTC-8" }] }, wst));
  const search = adding.find((x) => x.type === "search");
  assert.deepEqual([search.key, search.hidden, search.results[0].detail], ["add", false, "California, US · UTC-8"]);
  assert.ok(adding.find((x) => x.key === "do").hidden && adding.find((x) => x.key === "show").hidden, "the buttons step aside while searching");
  assert.ok(adding.some((x) => !x.hidden && x.text === "[@elsewhen.searchingPlaces]"));
  const here = plain(WS.sections({ rows, chosen: -1, choosingHere: true }, wst)).find((x) => x.type === "search");
  assert.deepEqual([here.key, here.placeholder], ["here", "[@elsewhen.whereAreYou]"]);
  const opts = plain(EM.searchZones(EM.zoneOptions("Europe/London\nAsia/Tokyo\n", []), "tok", 6));
  assert.equal(opts[0].value, "Asia/Tokyo");
  assert.deepEqual([WS.keyAction(0x01000007, ""), WS.keyAction(0, "a"), WS.keyAction(0, "x")], ["remove", "add", ""]);
});

// The small items: system update, keyboard layout, microphone.
const SU = load("plugin/fathom.system-update/Update.js", ["sections", "updateRows"]);
const KL = load("plugin/fathom.keyboard-layout/Layouts.js", ["sections", "layoutNames", "layouts"]);
const MI = load("plugin/fathom.microphone/Mic.js", ["sections"]);

test("system update: what's waiting, and Update now only when something is", () => {
  const s = plain(SU.sections({ available: true, lines: "omarchy 4.5.0-3 -> 4.6.0-1\nomarchy-dev-checkout 3 new commits on origin/dev\n" }, wst));
  assert.deepEqual(s[0].rows.map((r) => [r.name, r.detail]), [["omarchy", "4.5.0-3 → 4.6.0-1"], ["omarchy-dev-checkout 3 new commits on origin/dev", ""]]);
  assert.deepEqual(s[2].buttons.map((b) => b.key), ["update", "check"]);
  const none = plain(SU.sections({ available: false, lines: "" }, wst));
  assert.deepEqual([none[0].hidden, none[1].text], [true, "[su.none]"]);
  assert.deepEqual(none[2].buttons.map((b) => b.key), ["check"]);
});

test("keyboard layout: the layouts by name, the one in use lit", () => {
  const xkb = "models:\n- name: pc105\n  description: Generic 105-key PC\nlayouts:\n- layout: 'gb'\n  variant: ''\n  brief: 'en'\n  description: English (UK)\n" +
    "- layout: 'us'\n  variant: 'intl'\n  brief: 'en'\n  description: English (US, intl., with dead keys)\noptions:\n- name: x\n  description: y\n";
  const names = KL.layoutNames(xkb);
  assert.deepEqual(plain(names), { gb: "English (UK)", "us(intl)": "English (US, intl., with dead keys)" });
  const list = plain(KL.layouts({ layout: "gb,us,fr", variant: ",intl," }, names));
  assert.deepEqual(list, [{ code: "gb", name: "English (UK)" }, { code: "us(intl)", name: "English (US, intl., with dead keys)" }, { code: "fr", name: "fr" }]);
  const s = plain(KL.sections({ layouts: list, index: 1, methods: 0 }, wst));
  assert.deepEqual(s[0].rows.map((r) => r.active), [false, true, false]);
  assert.equal(s[1].hidden, true);
  assert.equal(plain(KL.sections({ layouts: list.slice(0, 1), index: 0, methods: 0 }, wst))[1].text, "[kb.one]");
  const im = plain(KL.sections({ layouts: list.slice(0, 1), methods: 2, method: "Mozc" }, wst));
  assert.deepEqual([im[2].hidden, im[2].rows[0].name], [false, "Mozc"]);
});

test("microphone: live or muted, the level, the inputs and who's listening", () => {
  const s = plain(MI.sections({ present: true, muted: false, volume: 0.42, apps: ["Zoom"],
    inputs: [{ key: "51", name: "Built-in", current: true }, { key: "60", name: "USB mic", current: false }] }, wst));
  assert.deepEqual([s[0].on, s[0].detail], [true, "[@bar.microphoneInUse]"]);
  assert.deepEqual([s[1].value, s[1].label], [0.42, "42%"]);
  assert.deepEqual(s[2].rows.map((r) => [r.key, r.active]), [["51", true], ["60", false]]);
  assert.deepEqual(s[3].rows.map((r) => r.name), ["Zoom"]);
  const muted = plain(MI.sections({ present: true, muted: true, volume: 0, inputs: [], apps: [] }, wst));
  assert.deepEqual([muted[0].on, muted[0].detail, muted[2].hidden, muted[3].hidden], [false, "[@bar.microphoneMuted]", true, true]);
  assert.deepEqual(plain(MI.sections({ present: false }, wst)), [{ type: "text", text: "[mic.none]", dim: true }]);
});

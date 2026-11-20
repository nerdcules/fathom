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
      for (const m of read(`plugin/${id}/${file}`).matchAll(/\bt\("([a-z][\w.]*)"\)/g)) used.add(m[1]);
    }
    for (const key of used) assert.ok(key in strings, `${id}: ${key} is in i18n/en.json`);
  }
});

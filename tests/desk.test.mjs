// Run with: node --test tests/
// Checks the desk's logic (Alt+Tab, Task view, Snap layouts, Quick
// settings): window order, stepping, snap geometry, and that nothing from a
// window (its title, say) can get into a Hyprland command.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import vm from "node:vm";

const dir = new URL("../desk/plugin/fathom.desk/", import.meta.url);
const read = (name) => readFileSync(new URL(name, dir), "utf8");

const D = {};
vm.runInNewContext(read("Desk.js").replace(/^\.pragma library\s*$/m, "") + `
  this.validAddress = validAddress; this.validWorkspace = validWorkspace;
  this.minimizedFrom = minimizedFrom; this.windowList = windowList; this.byWorkspace = byWorkspace;
  this.workspaceList = workspaceList; this.freeWorkspace = freeWorkspace;
  this.stepIndex = stepIndex; this.gridFit = gridFit; this.miniRect = miniRect;
  this.LAYOUTS = LAYOUTS; this.usableArea = usableArea; this.zoneRect = zoneRect; this.zoneOrder = zoneOrder;
  this.focusWindow = focusWindow; this.focusWorkspace = focusWorkspace; this.moveToWorkspace = moveToWorkspace;
  this.closeWindow = closeWindow; this.activate = activate; this.snap = snap; this.tile = tile;
  this.nextProfile = nextProfile; this.clampPercent = clampPercent;`, D);
// Values made inside the vm context: compare plain copies.
const plain = (v) => JSON.parse(JSON.stringify(v));

// The shape `hyprctl clients -j` gives.
const client = (address, id, history, extra = {}) => ({
  address, mapped: true, hidden: false, at: [0, 0], size: [100, 100], workspace: { id, name: String(id) },
  class: "app", title: "t", focusHistoryID: history, floating: false, fullscreen: 0, monitor: 0, ...extra,
});

test("Alt+Tab lists windows most recently used first", () => {
  const list = D.windowList([client("0xc", 2, 2), client("0xa", 1, 0), client("0xb", 1, 1)]);
  assert.deepEqual(plain(list.map((w) => w.address)), ["0xa", "0xb", "0xc"]);
});

test("scratchpads and unmapped windows stay out; minimized ones come in", () => {
  const list = D.windowList([
    client("0x1", 1, 0),
    client("0x2", -98, 1, { workspace: { id: -98, name: "special:scratchpad" } }),
    client("0x3", -99, 2, { workspace: { id: -99, name: "special:minimized" }, tags: ["omarchy-minimized-from-4"] }),
    client("0x4", 1, 3, { mapped: false }),
    client("not-an-address", 1, 4),
    null, "junk",
  ]);
  assert.deepEqual(plain(list.map((w) => [w.address, w.minimized, w.workspace])), [["0x1", false, 1], ["0x3", true, 4]]);
  assert.deepEqual(plain(D.windowList("nope")), []);
});

test("titles are plain, short and single-line", () => {
  const [w] = D.windowList([client("0x1", 1, 0, { title: "a\nb\u2028c" + "x".repeat(400) })]);
  assert.equal(w.title.length, 300);
  assert.doesNotMatch(w.title, /[\n\u2028]/);
});

test("the first Alt+Tab picks the window used before, then steps and wraps", () => {
  assert.equal(D.stepIndex(0, 5, 1, true), 1);
  assert.equal(D.stepIndex(0, 5, -1, true), 4);
  assert.equal(D.stepIndex(0, 1, 1, true), 0);
  assert.equal(D.stepIndex(-1, 0, 1, true), -1);
  assert.equal(D.stepIndex(4, 5, 1, false), 0);
  assert.equal(D.stepIndex(0, 5, -1, false), 4);
  assert.equal(D.stepIndex(2, 5, 1, false), 3);
});

test("Task view's workspaces are in order, with the one showing even if empty", () => {
  const ws = D.workspaceList([{ id: 5, windows: 1 }, { id: 1, windows: 2 }, { id: -98, windows: 1 }], 3);
  assert.deepEqual(plain(ws.map((w) => w.id)), [1, 3, 5]);
  assert.equal(D.freeWorkspace(ws), 2);
  assert.equal(D.freeWorkspace([]), 1);
  const groups = D.byWorkspace(D.windowList([client("0x1", 1, 0), client("0x2", 1, 1), client("0x3", 2, 2)]));
  assert.deepEqual(plain(Object.keys(groups)), ["1", "2"]);
});

test("cards fill the space as large as they can", () => {
  const one = D.gridFit(1, 1000, 500, 16 / 9, 10);
  assert.equal(one.columns, 1);
  assert.ok(one.cardHeight <= 500 && one.cardWidth <= 1000);
  const four = D.gridFit(4, 1600, 900, 16 / 9, 20);
  assert.equal(four.columns, 2);
  assert.deepEqual(plain(D.gridFit(0, 100, 100, 1, 0)), { columns: 1, cardWidth: 0, cardHeight: 0 });
});

test("a window off to the side of its monitor is clipped in the picture", () => {
  const mon = { x: 0, y: 0, width: 2000, height: 1000 };
  assert.deepEqual(plain(D.miniRect({ at: [1000, 0], size: [1000, 500] }, mon)), { x: 0.5, y: 0, w: 0.5, h: 0.5 });
  assert.deepEqual(plain(D.miniRect({ at: [-500, 0], size: [1000, 1000] }, mon)), { x: 0, y: 0, w: 0.25, h: 1 });
  assert.equal(D.miniRect({ at: [-1117, 51], size: [1110, 1473] }, mon), null);
});

test("snap zones leave the bar and the gaps alone", () => {
  // This laptop: 2496x1664 at scale 1.0833334, the bar reserving 39 at the top.
  const area = D.usableArea({ x: 0, y: 0, width: 2496, height: 1664, scale: 1.0833334, reserved: [0, 39, 0, 0], transform: 0 }, 12);
  assert.deepEqual(plain(area), { x: 12, y: 51, width: 2280, height: 1473 });
  const [left, right] = D.LAYOUTS[0].zones.map((z) => D.zoneRect(z, area, 10));
  assert.deepEqual(plain(left), { x: 12, y: 51, width: 1135, height: 1473 });
  assert.deepEqual(plain(right), { x: 1157, y: 51, width: 1135, height: 1473 });
  assert.equal(left.x + left.width + 10, right.x);
  // A quarter touches two edges and has gaps on the other two.
  const q = D.zoneRect(D.LAYOUTS[4].zones[3], area, 10);
  assert.equal(q.x + q.width, 12 + 2280);
  assert.equal(q.y + q.height, 51 + 1473);
  // A portrait monitor swaps width and height.
  assert.equal(D.usableArea({ width: 1000, height: 2000, scale: 1, transform: 1, reserved: [0, 0, 0, 0] }, 0).width, 2000);
  assert.equal(D.usableArea(null, 0), null);
});

test("every zone of every layout fits inside the usable area", () => {
  const area = { x: 10, y: 50, width: 1900, height: 1000 };
  for (const layout of D.LAYOUTS) {
    for (const z of layout.zones) {
      const r = D.zoneRect(z, area, 8);
      assert.ok(r.x >= area.x && r.y >= area.y && r.width > 0 && r.height > 0, layout.id);
      assert.ok(r.x + r.width <= area.x + area.width && r.y + r.height <= area.y + area.height, layout.id);
    }
  }
  assert.equal(D.zoneOrder().length, D.LAYOUTS.reduce((n, l) => n + l.zones.length, 0));
});

test("commands take only checked addresses, workspaces and numbers", () => {
  assert.equal(D.focusWindow("0x55cb94a030a0"), 'hl.dsp.focus({ window = "address:0x55cb94a030a0" })');
  for (const bad of ['0x1" }) hl.exec_cmd("rm', "0x", "55cb", "", null, 7]) {
    assert.equal(D.focusWindow(bad), null);
    assert.equal(D.closeWindow(bad), null);
    assert.equal(D.moveToWorkspace(bad, 1, false), null);
    assert.deepEqual(plain(D.snap(bad, { x: 0, y: 0, width: 10, height: 10 })), []);
  }
  assert.equal(D.focusWorkspace(3), 'hl.dsp.focus({ workspace = "3" })');
  for (const bad of [0, -1, 1.5, "3", NaN, 100000]) assert.equal(D.focusWorkspace(bad), null);
  assert.equal(D.moveToWorkspace("0xab", 2, false), 'hl.dsp.window.move({ workspace = "2", follow = false, window = "address:0xab" })');
  assert.deepEqual(plain(D.snap("0xab", { x: 1.4, y: "2", width: 100, height: NaN })), []);
  assert.deepEqual(plain(D.snap("0xab", { x: 12, y: 51, width: 1135, height: 1473 })), [
    'hl.dsp.window.float({ action = "on", window = "address:0xab" })',
    'hl.dsp.window.resize({ x = 1135, y = 1473, window = "address:0xab" })',
    'hl.dsp.window.move({ x = 12, y = 51, window = "address:0xab" })',
    'hl.dsp.window.alter_zorder({ mode = "top", window = "address:0xab" })',
  ]);
});

test("bringing back a minimized window returns it where it came from", () => {
  const [w] = D.windowList([client("0x9", -99, 0, { workspace: { id: -99, name: "special:minimized" }, tags: ["omarchy-minimized-from-3"] })]);
  assert.deepEqual(plain(D.activate(w, 1)), [
    'hl.dsp.window.move({ workspace = "3", follow = true, window = "address:0x9" })',
    'hl.dsp.window.tag({ tag = "-omarchy-minimized-from-3", window = "address:0x9" })',
    'hl.dsp.focus({ window = "address:0x9" })',
  ]);
  // No tag: to the workspace showing.
  const [u] = D.windowList([client("0x8", -99, 0, { workspace: { id: -99, name: "special:minimized" } })]);
  assert.equal(D.activate(u, 2)[0], 'hl.dsp.window.move({ workspace = "2", follow = true, window = "address:0x8" })');
  assert.deepEqual(plain(D.activate(D.windowList([client("0x7", 1, 0)])[0], 1)), ['hl.dsp.focus({ window = "address:0x7" })']);
});

test("Quick settings steps power profiles and keeps brightness in range", () => {
  assert.equal(D.nextProfile("balanced", ["power-saver", "balanced", "performance"]), "performance");
  assert.equal(D.nextProfile("performance", ["power-saver", "balanced", "performance"]), "power-saver");
  assert.equal(D.nextProfile("odd", ["balanced"]), "balanced");
  assert.equal(D.nextProfile("x", []), null);
  assert.equal(D.clampPercent(0), 1);
  assert.equal(D.clampPercent(140), 100);
  assert.equal(D.clampPercent("40"), 40);
  assert.equal(D.clampPercent("lots"), null);
});

test("every type the desk uses is listed in qmldir, and its text is plain", () => {
  const qml = readdirSync(dir).filter((f) => f.endsWith(".qml"));
  const listed = read("qmldir").split("\n").filter(Boolean).map((l) => l.trim().split(/\s+/).at(-1));
  for (const file of qml) {
    assert.ok(listed.includes(file), `${file} missing from qmldir`);
    const src = read(file);
    if (file !== "Label.qml") assert.equal((src.match(/^\s*Text \{/gm) || []).length, 0, `${file}: use Label, not Text`);
    assert.doesNotMatch(src, /textFormat: Text\.(RichText|StyledText|AutoText|MarkdownText)/, file);
  }
});

test("every string the desk asks for is in en.json", () => {
  const en = JSON.parse(read("i18n/en.json"));
  const qml = readdirSync(dir).filter((f) => f.endsWith(".qml"));
  const used = new Set();
  for (const file of qml) for (const m of read(file).matchAll(/\b(?:t|tn)\("([a-zA-Z.]+)"/g)) used.add(m[1]);
  // Keys built at runtime.
  for (const l of D.LAYOUTS) used.add(`snap.layout.${l.id}`);
  for (const p of ["power-saver", "balanced", "performance"]) used.add(`quick.profile.${p}`);
  for (const key of used) if (!key.endsWith(".")) assert.ok(key in en, `${key} missing from en.json`);
});

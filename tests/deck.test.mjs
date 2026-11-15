// Run with: node --test tests/
// Checks the Command Deck's formatting and its handling of untrusted text
// (container names, process names and the like come from the machine).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import vm from "node:vm";

const dir = new URL("../deck/plugin/fathom.deck/", import.meta.url);
const read = (name) => readFileSync(new URL(name, dir), "utf8");

const F = {};
vm.runInNewContext(read("Format.js").replace(/^\.pragma library\s*$/m, "") + `
  this.bytes = bytes; this.percent = percent; this.level = level;
  this.containerHealth = containerHealth; this.hostPorts = hostPorts;
  this.groupContainers = groupContainers; this.countRunning = countRunning;
  this.byKind = byKind; this.sum = sum; this.agentBusy = agentBusy;
  this.uptime = uptime; this.dockerSpace = dockerSpace;
  this.validContainerName = validContainerName;
  this.SEGMENTS = SEGMENTS; this.diskSegments = diskSegments; this.totalBytes = totalBytes;
  this.ids = ids; this.anyRoot = anyRoot; this.ago = ago; this.forecast = forecast;
  this.updateCount = updateCount;`, F);
const qmlFiles = readdirSync(dir).filter((f) => f.endsWith(".qml"));

test("sizes read like people write them", () => {
  assert.equal(F.bytes(0), "0 B");
  assert.equal(F.bytes(999), "999 B");
  assert.equal(F.bytes(83_900_000), "83.9 MB");
  assert.equal(F.bytes(254_000_000), "254 MB");
  assert.equal(F.bytes(33_211_731_968), "33.2 GB");
  assert.equal(F.bytes(-5), "0 B");
  assert.equal(F.bytes("junk"), "0 B");
});

test("disk levels warn at 85% and alarm at 95%", () => {
  assert.equal(F.level(F.percent(84, 100)), "ok");
  assert.equal(F.level(F.percent(85, 100)), "warn");
  assert.equal(F.level(F.percent(95, 100)), "bad");
  assert.equal(F.percent(5, 0), 0);
  assert.equal(F.percent(200, 100), 100);
});

test("container health follows docker's state and status", () => {
  const h = (state, status) => F.containerHealth({ state, status });
  assert.equal(h("running", "Up 3 days"), "ok");
  assert.equal(h("running", "Up 2 hours (healthy)"), "ok");
  assert.equal(h("running", "Up 1 minute (unhealthy)"), "bad");
  assert.equal(h("running", "Up 5 seconds (health: starting)"), "warn");
  assert.equal(h("restarting", "Restarting (1) 5 seconds ago"), "warn");
  assert.equal(h("exited", "Exited (0) 6 days ago"), "stopped");
  assert.equal(h("exited", "Exited (137) 2 hours ago"), "bad");
  assert.equal(h("created", "Created"), "stopped");
  assert.equal(F.containerHealth(null), "stopped");
});

test("only host ports are shown, each once", () => {
  assert.equal(F.hostPorts("0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp"), ":8080");
  assert.equal(F.hostPorts("127.0.0.1:5432->5432/tcp"), ":5432");
  assert.equal(F.hostPorts("5432/tcp"), "");
  assert.equal(F.hostPorts(""), "");
  assert.equal(F.hostPorts("0.0.0.0:1->1/tcp, 0.0.0.0:2->2/tcp, 0.0.0.0:3->3/tcp, 0.0.0.0:4->4/tcp"), ":1 :2 :3");
});

test("containers group by compose project, standalone last", () => {
  const groups = F.groupContainers([
    { name: "postgres18", project: "" },
    { name: "api", project: "shop" },
    { name: "app", project: "moa" },
    { name: "redis", project: "shop" },
  ]);
  assert.deepEqual([...groups.map((g) => g.project)], ["moa", "shop", ""]);
  assert.deepEqual([...groups[1].containers.map((c) => c.name)], ["api", "redis"]);
  assert.equal(F.groupContainers(undefined).length, 0);
});

test("counts and sums tolerate missing data", () => {
  assert.equal(F.countRunning([{ state: "running" }, { state: "exited" }]), 1);
  assert.equal(F.countRunning(null), 0);
  assert.equal(F.byKind([{ kind: "app" }, { kind: "tooling" }], "tooling").length, 1);
  assert.equal(F.sum([{ rss: 1 }, { rss: "2" }, {}], "rss"), 3);
  assert.equal(F.agentBusy({ cpu: 2.9 }), false);
  assert.equal(F.agentBusy({ cpu: 3 }), true);
  assert.deepEqual({ ...F.uptime(386832) }, { days: 4, hours: 11, minutes: 27 });
});

test("docker's disk rows are picked out by type", () => {
  const s = F.dockerSpace([
    { type: "Images", size: "20.57GB" },
    { type: "Build Cache", size: "20.73GB" },
    { type: "Local Volumes", size: "606.4MB" },
  ]);
  assert.equal(s.images, "20.57GB");
  assert.equal(s.cache, "20.73GB");
  assert.equal(s.volumes, "606.4MB");
});

test("the deck only acts on names docker could have made", () => {
  assert.ok(F.validContainerName("postgres18"));
  assert.ok(F.validContainerName("moa-app-1"));
  assert.ok(F.validContainerName("a_b.c"));
  for (const bad of ["", "-rm", "a b", "a;rm -rf ~", "<b>x</b>", "x".repeat(129), "$(id)", null]) {
    assert.ok(!F.validContainerName(bad), String(bad));
  }
});

test("every piece of text in the deck is plain text", () => {
  // All text goes through Label, which sets PlainText.
  assert.match(read("Label.qml"), /^Text \{\s*textFormat: Text\.PlainText/m);
  for (const file of qmlFiles) {
    const src = read(file);
    if (file !== "Label.qml") assert.equal((src.match(/^\s*Text \{/gm) || []).length, 0, `${file}: use Label, not Text`);
    assert.doesNotMatch(src, /textFormat: Text\.(RichText|StyledText|AutoText|MarkdownText)/, file);
  }
});

test("every type the deck uses is listed in qmldir", () => {
  const listed = read("qmldir").split("\n").filter(Boolean).map((l) => l.trim().split(/\s+/).at(-1));
  for (const file of qmlFiles) assert.ok(listed.includes(file), `${file} missing from qmldir`);
});

test("every string the deck asks for is in en.json", () => {
  const en = JSON.parse(read("i18n/en.json"));
  const used = new Set();
  for (const file of qmlFiles) {
    for (const m of read(file).matchAll(/\b(?:t|tn)\("([a-zA-Z.]+)"/g)) used.add(m[1]);
  }
  // Keys built at runtime.
  used.add("ai.inEditor").add("ai.inTerminal");
  for (const id of ["trash", "docker-cache", "docker-images", "nuget", "npm", "uv", "pip", "yay", "pacman", "journal"]) {
    used.add(`care.reclaim.${id}`).add(`care.reclaimDetail.${id}`);
  }
  for (const key of F.SEGMENTS) used.add(`care.part.${key}`);
  for (const unit of ["days", "weeks", "months"]) used.add(`care.forecast.${unit}`);
  for (const unit of ["minutes", "hours", "days"]) used.add(`care.ago.${unit}`);
  assert.ok(used.size > 100, `found only ${used.size} keys`);
  for (const key of used) {
    if (key.endsWith(".")) continue; // a prefix completed at runtime, covered above
    assert.ok(key in en, `missing ${key}`);
  }
  for (const [key, value] of Object.entries(en)) {
    if (typeof value === "object") assert.ok(value.one && value.other, `${key} needs one and other`);
  }
});

test("Care's cleanable items match the script's", () => {
  const script = readFileSync(new URL("../care/bin/fathom-care", import.meta.url), "utf8");
  const items = script.match(/^CLEAN_ITEMS=\(([^)]*)\)/m)[1].trim().split(/\s+/);
  const en = JSON.parse(read("i18n/en.json"));
  for (const id of items) {
    assert.ok(`care.reclaim.${id}` in en, `no label for ${id}`);
    assert.ok(`care.reclaimDetail.${id}` in en, `no detail for ${id}`);
  }
});

test("disk parts add up to no more than what's used", () => {
  const disk = { size: 1000, used: 500, breakdown: { docker: 300, models: 0, caches: 100, projects: 50, home: 150 } };
  const parts = F.diskSegments(disk);
  // Docker double-counts shared layers: 600 known > 500 used, so no
  // "system" part and everything scaled to fit.
  assert.deepEqual([...parts.map((p) => p.key)], ["docker", "caches", "projects", "home"]);
  const share = parts.reduce((t, p) => t + p.share, 0);
  assert.ok(Math.abs(share - 0.5) < 1e-9, String(share));

  const roomy = F.diskSegments({ size: 1000, used: 800, breakdown: { docker: 100, models: 50, caches: 50, projects: 100, home: 200 } });
  assert.equal(roomy[0].key, "system");
  assert.equal(roomy[0].bytes, 300);
  assert.equal(F.diskSegments({ size: 1, used: 1 }).length, 0);
  assert.equal(F.diskSegments(null).length, 0);
});

test("reclaim helpers", () => {
  const items = [{ id: "trash", bytes: 10, root: false }, { id: "journal", bytes: 5, root: true }];
  assert.equal(F.totalBytes(items), 15);
  assert.deepEqual([...F.ids(items)], ["trash", "journal"]);
  assert.equal(F.anyRoot(items), true);
  assert.equal(F.anyRoot(items.slice(0, 1)), false);
  assert.equal(F.anyRoot(undefined), false);
});

test("times read in the largest whole unit", () => {
  assert.deepEqual({ ...F.ago(0, 30) }, { unit: "minutes", n: 1 });
  assert.deepEqual({ ...F.ago(0, 600) }, { unit: "minutes", n: 10 });
  assert.deepEqual({ ...F.ago(0, 7200) }, { unit: "hours", n: 2 });
  assert.deepEqual({ ...F.ago(0, 3 * 86400) }, { unit: "days", n: 3 });
  assert.equal(F.forecast(null), null);
  assert.equal(F.forecast(400), null);
  assert.deepEqual({ ...F.forecast(5) }, { unit: "days", n: 5 });
  assert.deepEqual({ ...F.forecast(23) }, { unit: "weeks", n: 3 });
  assert.deepEqual({ ...F.forecast(100) }, { unit: "months", n: 3 });
});

test("updates are counted across packages, AUR and firmware", () => {
  assert.equal(F.updateCount(null), 0);
  assert.equal(F.updateCount({ packages: [1, 2], aur: [3], firmware: 2 }), 5);
  assert.equal(F.updateCount({ packages: [], aur: [] }), 0);
});

// Run with: node --test tests/
// Checks the Command Deck's formatting and its handling of untrusted text
// (container names, process names and the like come from the machine).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
  this.validContainerName = validContainerName;`, F);

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
  const view = read("DeckView.qml");
  // All text goes through the Label component, which sets PlainText.
  const textItems = view.match(/^\s*Text \{/gm) || [];
  assert.equal(textItems.length, 0, "use Label, not Text");
  assert.match(view, /component Label: Text \{\s*textFormat: Text\.PlainText/);
  assert.doesNotMatch(view, /textFormat: Text\.(RichText|StyledText|AutoText|MarkdownText)/);
});

test("every string the deck asks for is in en.json", () => {
  const en = JSON.parse(read("i18n/en.json"));
  const used = new Set();
  for (const file of ["DeckView.qml", "Panel.qml"]) {
    for (const m of read(file).matchAll(/\b(?:t|tn)\("([a-zA-Z.]+)"/g)) used.add(m[1]);
  }
  // Keys chosen at runtime.
  used.add("ai.inEditor").add("ai.inTerminal");
  assert.ok(used.size > 30, `found only ${used.size} keys`);
  for (const key of used) assert.ok(key in en, `missing ${key}`);
  for (const [key, value] of Object.entries(en)) {
    if (typeof value === "object") assert.ok(value.one && value.other, `${key} needs one and other`);
  }
});

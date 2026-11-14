// Run with: node --test tests/
// Checks the mini-player widget's handling of untrusted video titles.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../player/plugin/fathom.player/Sanitize.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "");
const S = {};
vm.runInNewContext(src + "\nthis.plain = plain; this.ellipsize = ellipsize; this.clock = clock;", S);

test("markup-shaped titles cannot become rich text", () => {
  const out = S.plain('<img src="https://example.invalid/tracker">Song & <b>Dance</b>');
  assert.ok(!/[<>&]/.test(out), out);
  assert.equal(out, "‹img src=\"https://example.invalid/tracker\"›Song ＆ ‹b›Dance‹/b›");
});

test("control and line-separator characters become spaces", () => {
  assert.equal(S.plain("a\u0000b\nc\u2028d\u009fe"), "a b c d e");
});

test("length is capped before display", () => {
  assert.equal(S.plain("x".repeat(1000), 300).length, 300);
  assert.equal(S.plain("x".repeat(1000)).length, 300);
});

test("missing values are empty", () => {
  assert.equal(S.plain(undefined), "");
  assert.equal(S.plain(null), "");
});

test("ellipsize shortens with an ellipsis", () => {
  assert.equal(S.ellipsize("Live coding: RAG in C#", 10), "Live codi…");
  assert.equal(S.ellipsize("short", 10), "short");
});

test("clock formats seconds", () => {
  assert.equal(S.clock(75), "1:15");
  assert.equal(S.clock(3725), "1:02:05");
  assert.equal(S.clock(-1), "--:--");
  assert.equal(S.clock("nope"), "--:--");
});

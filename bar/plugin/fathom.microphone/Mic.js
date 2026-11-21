.pragma library

// Fathom's microphone dropdown (#14): what it shows, as the kit's factory
// draws it. Node tests: tests/bar.test.mjs.

// `v`: present (a microphone to show), muted, volume (0..1), inputs
// ([{key, name, current}]), apps ([names using it]).
function sections(v, t) {
  if (!v.present) return [{ type: "text", text: t("mic.none"), dim: true }]
  var inputs = v.inputs || []
  var apps = v.apps || []
  return [
    { type: "switch", key: "live", glyph: String.fromCodePoint(v.muted ? 0xF036D : 0xF036C),
      name: t("mic.title"), detail: t(v.muted ? "@bar.microphoneMuted" : (apps.length > 0 ? "@bar.microphoneInUse" : "@bar.microphoneLive")),
      on: !v.muted },
    { type: "slider", key: "level", glyph: String.fromCodePoint(0xF036C), tip: t("mic.level"),
      value: Math.max(0, Math.min(1, Number(v.volume) || 0)), label: Math.round((Number(v.volume) || 0) * 100) + "%" },
    { type: "rows", key: "input", title: t("mic.inputs"), hidden: inputs.length < 2, rows: inputs.map(function(i) {
      return { key: i.key, glyph: String.fromCodePoint(0xF036C), name: i.name, active: !!i.current }
    }) },
    { type: "rows", key: "apps", title: t("mic.apps"), hidden: apps.length === 0, rows: apps.map(function(a, i) {
      return { key: String(i), glyph: String.fromCodePoint(0xF08C6), name: a, clickable: false }
    }) }
  ]
}

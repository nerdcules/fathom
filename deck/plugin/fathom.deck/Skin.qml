pragma Singleton
import QtQuick
import "Format.js" as F

// Shared look for the deck's pages: theme colours, font, scale, motion,
// strings and number formatting. Panel.qml (or a test harness) sets these
// once; every part reads them from here.
QtObject {
  property color fg: "#e6f0ff"
  property color bg: "#0a1020"
  property color accent: "#4cc9f0"
  property color urgent: "#ff6b81"
  property color ok: "#3ddc97"
  property color warn: "#ffb547"
  property color violet: "#9d8cff"
  property color blue: "#5b8cff"
  property string fontFamily: "monospace"
  property real motion: 1
  property real u: 1
  property var locale: Qt.locale()
  // Translations: an object with t(key) and tn(key, count).
  property var strings: null
  // Number formatting: fmt(value, decimals) -> string.
  property var fmt: function(v, d) { return Number(v).toFixed(d || 0) }
  // The item tooltips and dialogs draw on top of.
  property Item overlay: null
  // Ask before doing something: ask(title, body, confirmText, onConfirm).
  // DeckView provides it.
  property var ask: function(title, body, confirmText, onConfirm) { console.warn("fathom.deck: no dialog to ask with") }

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)

  function t(key) { return strings ? strings.t(key) : key }
  function tn(key, n) { return strings ? strings.tn(key, n) : key }
  function n(v, d) { return fmt(v, d || 0) }
  function size(v) { return F.bytes(v, fmt) }
  function levelColor(l) { return l === "bad" ? urgent : (l === "warn" ? warn : (l === "ok" ? ok : dim)) }
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}

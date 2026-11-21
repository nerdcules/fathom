pragma Singleton
import QtQuick
import "Format.js" as F

// Fathom's look, in one place (#22): theme colours, font, scale, motion,
// strings and number formatting. install.sh copies this kit into each shell
// plugin that draws with it (the deck, the desk, the bar's dropdowns), so
// each has its own copy of this file but no copy differs: a plugin can only
// load its own files. In the repo each plugin's kit/ is a link to this
// folder.
//
// Who sets it: the deck's and the desk's Panel.qml, and a dropdown's
// DropTheme.qml, bind the theme into it (or a test harness sets it); every
// part reads it from here.
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
  // Whether Hyprland blurs what's behind Fathom's panels. Omarchy turns blur
  // off desktop-wide unless a Glassy mode is on, and then see-through
  // surfaces show sharp text behind them, so they go solid: over white
  // terminal text (0.92 grayscale), a surface of this colour at alpha 0.94
  // measured 0.110 at its brightest against its own 0.059, faint but
  // legible; at 1.0, 0.059 (2026-11-15). The panels ask Hyprland each time
  // they open.
  property bool glass: false
  // The look from Personalise (fathom-look), as applied: corners as
  // Hyprland rounds windows (Style.cornerRadius), how opaque panels are
  // over blur and how strong their border is (the theme's menu alpha and
  // border alpha), and the accent's glow along their top (look.json).
  // The values here are Fathom's own look.
  property int radius: 22
  property real glassAlpha: 0.9
  property real edgeAlpha: 0.25
  property bool glow: true
  property var locale: Qt.locale()
  // Translations: an object with t(key) and tn(key, count).
  property var strings: null
  // Number formatting: fmt(value, decimals) -> string.
  property var fmt: function(v, d) { return Number(v).toFixed(d || 0) }
  // The item tooltips (Tip.qml) and dialogs draw on top of; none, no tips.
  property Item overlay: null
  // Ask before doing something: ask(title, body, confirmText, onConfirm).
  // The deck's DeckView provides it.
  property var ask: function(title, body, confirmText, onConfirm) { console.warn("fathom: no dialog to ask with") }

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  // A panel, as the Start menu draws its own: the look's opacity over
  // blur, else solid.
  readonly property real panelAlpha: glass ? glassAlpha : 1
  // A dimmed screen behind a view.
  readonly property real scrimAlpha: glass ? 0.55 : 1

  // One ladder of states for every control (#18), the strengths Omarchy's
  // own controls use (theme/shell.toml): hover and pressed tint the accent;
  // selected (on, chosen, a list's cursor) fills with it and edges it, and
  // brightens under the pointer.
  readonly property color hoverFill: tint(accent, 0.12)
  readonly property color pressedFill: tint(accent, 0.22)
  readonly property color selectedFill: tint(accent, 0.36)
  readonly property color selectedEdge: tint(accent, 0.8)
  function stateFill(idle, selected, hovered, pressed) {
    if (selected) return tint(accent, pressed ? 0.55 : (hovered ? 0.45 : 0.36))
    return pressed ? pressedFill : (hovered ? hoverFill : idle)
  }

  function t(key) { return strings ? strings.t(key) : key }
  function tn(key, n) { return strings ? strings.tn(key, n) : key }
  function n(v, d) { return fmt(v, d || 0) }
  function size(v) { return F.bytes(v, fmt) }
  function levelColor(l) { return l === "bad" ? urgent : (l === "warn" ? warn : (l === "ok" ? ok : dim)) }
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function ms(n) { return Math.round(n * motion) }
}

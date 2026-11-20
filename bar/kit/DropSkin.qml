pragma Singleton
import QtQuick

// The look of Fathom's bar dropdowns (#14): the desk's Quick settings look
// (desk/plugin/fathom.desk/Skin.qml, which this copies). DropCard.qml sets
// the theme colours, font, scale and strings; every part reads them here.
QtObject {
  property color fg: "#e6f0ff"
  property color bg: "#0a1020"
  property color accent: "#4cc9f0"
  property color urgent: "#ff6b81"
  property color ok: "#3ddc97"
  property color warn: "#ffb547"
  property color violet: "#9d8cff"
  property string fontFamily: "monospace"
  property real motion: 1
  property real u: 1
  // Whether Hyprland blurs what's behind the desk's glass (see the deck's
  // Skin.qml). Without blur, glass goes solid: over white terminal text
  // (0.92 grayscale), a surface of this colour at alpha 0.94 measured 0.110
  // at its brightest against its own 0.059, faint but legible; at 1.0, 0.059
  // (2026-11-15).
  property bool glass: false
  // The look from Personalise (fathom-look), as applied: corners as
  // Hyprland rounds windows (Style.cornerRadius), how opaque panels are
  // over blur and how strong their border is (the theme's menu alpha and
  // border alpha), and the accent's glow along their top (look.json).
  // DropCard.qml binds these; the values here are Fathom's own look.
  property int radius: 22
  property real glassAlpha: 0.9
  property real edgeAlpha: 0.25
  property bool glow: true
  property var strings: null

  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  // A panel, as the Start menu draws its own: the look's opacity over
  // blur, else solid.
  readonly property real panelAlpha: glass ? glassAlpha : 1
  // A dimmed screen behind a view.
  readonly property real scrimAlpha: glass ? 0.55 : 1

  function t(key) { return strings ? strings.t(key) : key }
  function tn(key, n) { return strings ? strings.tn(key, n) : key }
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function ms(n) { return Math.round(n * motion) }
}

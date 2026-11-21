import QtQuick
import "."

// A status mark (#17). The shape says the state and the colour repeats it,
// so the states tell apart without colour too: green and red are 1.55:1
// apart in lightness, green and amber 1.01:1. From the tone: ok (green) a
// filled disc, warn (amber) a ring, bad (red) a diamond, idle (dim) a hollow
// disc; any other colour (the accent, a category) a filled disc. In the
// same 8 px box as before, so rows don't move.
Item {
  id: dot
  property color tone: Skin.ok
  readonly property string shape: Qt.colorEqual(tone, Skin.urgent) ? "diamond"
    : Qt.colorEqual(tone, Skin.warn) ? "ring"
    : Qt.colorEqual(tone, Skin.dim) ? "hollow" : "disc"
  width: 8 * Skin.u
  height: width
  Accessible.ignored: true

  Rectangle {
    objectName: "round"
    anchors.fill: parent
    visible: dot.shape !== "diamond"
    radius: width / 2
    color: dot.shape === "disc" ? dot.tone : "transparent"
    border.width: dot.shape === "ring" ? Math.max(2, Math.round(2 * Skin.u))
      : (dot.shape === "hollow" ? Math.max(1, Math.round(1.5 * Skin.u)) : 0)
    border.color: dot.tone
  }
  Rectangle {
    objectName: "diamond"
    anchors.centerIn: parent
    visible: dot.shape === "diamond"
    width: parent.width * 0.8
    height: width
    rotation: 45
    antialiasing: true
    color: dot.tone
  }
}

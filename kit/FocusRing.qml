import QtQuick
import "."

// Where the keyboard is (#16): 2 px of the foreground, 2 px outside the part
// that has focus, so it reads apart from selected (the accent's fill and
// edge): 16.49:1 against the panel, 7.30:1 against a selected fill. Put one
// inside a focusable part; it shows while that part has focus. `target`
// draws it around a sibling instead (a slider's knob), `shown` says when.
Rectangle {
  objectName: "focusRing"
  property Item target: parent
  property bool shown: target ? target.activeFocus : false
  readonly property real gap: 2
  readonly property real targetRadius: target && target.radius !== undefined ? target.radius : 0

  x: (target && target !== parent ? target.x : 0) - gap - border.width
  y: (target && target !== parent ? target.y : 0) - gap - border.width
  width: target ? target.width + 2 * (gap + border.width) : 0
  height: target ? target.height + 2 * (gap + border.width) : 0
  radius: targetRadius > 0 ? targetRadius + gap + border.width : 0
  color: "transparent"
  border.width: 2
  border.color: Skin.fg
  visible: shown
  z: 100
}

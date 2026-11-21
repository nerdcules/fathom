import QtQuick
import "."

// A small label above the item it explains, drawn on the deck's overlay.
Rectangle {
  id: tip
  property Item target: null
  property string text: ""
  property bool show: false
  parent: Skin.overlay
  z: 100
  visible: opacity > 0
  opacity: show ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 * Skin.motion } }
  width: tipText.implicitWidth + 16 * Skin.u
  height: tipText.implicitHeight + 10 * Skin.u
  radius: Skin.corner(6)
  color: Skin.tint(Skin.bg, 0.96)
  border.width: 1
  border.color: Skin.faint
  x: {
    if (!target || !show || !parent) return 0
    var p = target.mapToItem(parent, target.width / 2, 0)
    return Math.max(8, Math.min(parent.width - width - 8, p.x - width / 2))
  }
  y: (!target || !show || !parent) ? 0 : target.mapToItem(parent, 0, 0).y - height - 6 * Skin.u
  Label { id: tipText; anchors.centerIn: parent; text: tip.text; font.pixelSize: Skin.text.detail }
}

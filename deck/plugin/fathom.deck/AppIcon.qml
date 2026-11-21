import QtQuick
import "kit"
import "."

// An app's icon, or a lettered tile when it has none (or a glyph for
// Fathom's own items).
Item {
  id: icon
  property string source: ""
  property string glyph: ""
  property string name: ""
  property real size: 40 * Skin.u
  width: size
  height: size
  Image {
    id: img
    anchors.fill: parent
    source: icon.source
    sourceSize.width: icon.size * 2
    sourceSize.height: icon.size * 2
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    visible: status === Image.Ready
  }
  Rectangle {
    anchors.fill: parent
    visible: img.status !== Image.Ready
    radius: icon.size * 0.28
    color: Skin.tint(Skin.accent, icon.glyph !== "" ? 0.16 : 0.22)
    border.width: 1
    border.color: Skin.tint(Skin.accent, 0.35)
    Label {
      anchors.centerIn: parent
      text: icon.glyph !== "" ? icon.glyph : String(icon.name || "?").charAt(0).toUpperCase()
      color: Skin.accent
      font.pixelSize: icon.size * 0.45
      font.weight: Font.DemiBold
    }
  }
}

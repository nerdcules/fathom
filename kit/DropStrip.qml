import QtQuick
import "."

// A row of small tiles of the same width (the weather's coming days): a
// glyph in the accent, a name, and a line under it. Read-only.
Row {
  id: strip
  // [{key, glyph, name, detail}]
  property var items: []
  readonly property real tile: items.length > 0 ? (width - spacing * (items.length - 1)) / items.length : width
  spacing: 8 * Skin.u

  Repeater {
    model: strip.items.length
    delegate: Rectangle {
      required property int index
      readonly property var item: strip.items[index] || ({})
      objectName: "tile " + (item.key || index)
      width: strip.tile
      height: tileColumn.implicitHeight + 20 * Skin.u
      radius: 12 * Skin.u
      color: Skin.tint(Skin.fg, 0.06)
      border.width: 1
      border.color: Skin.tint(Skin.fg, 0.1)
      Column {
        id: tileColumn
        anchors.centerIn: parent
        width: parent.width - 16 * Skin.u
        spacing: 3
        Label {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.glyph || ""
          color: Skin.accent
          font.pixelSize: 22 * Skin.u
        }
        Label {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.name || ""
          font.pixelSize: 12 * Skin.u
          font.weight: Font.DemiBold
        }
        Label {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.detail || ""
          color: Skin.dim
          font.pixelSize: 11 * Skin.u
        }
      }
    }
  }
}

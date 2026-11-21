import QtQuick
import "."

// A row of small tiles of the same width (the weather's coming days): a
// glyph in the accent, a name, and a line under it. Read-only.
Row {
  id: strip
  // [{key, glyph, name, detail}]
  property var items: []
  readonly property real tile: items.length > 0 ? (width - spacing * (items.length - 1)) / items.length : width
  spacing: 8 * DropSkin.u

  Repeater {
    model: strip.items.length
    delegate: Rectangle {
      required property int index
      readonly property var item: strip.items[index] || ({})
      objectName: "tile " + (item.key || index)
      width: strip.tile
      height: tileColumn.implicitHeight + 20 * DropSkin.u
      radius: 12 * DropSkin.u
      color: DropSkin.tint(DropSkin.fg, 0.06)
      border.width: 1
      border.color: DropSkin.tint(DropSkin.fg, 0.1)
      Column {
        id: tileColumn
        anchors.centerIn: parent
        width: parent.width - 16 * DropSkin.u
        spacing: 3
        DropLabel {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.glyph || ""
          color: DropSkin.accent
          font.pixelSize: 22 * DropSkin.u
        }
        DropLabel {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.name || ""
          font.pixelSize: 12 * DropSkin.u
          font.weight: Font.DemiBold
        }
        DropLabel {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: item.detail || ""
          color: DropSkin.dim
          font.pixelSize: 11 * DropSkin.u
        }
      }
    }
  }
}

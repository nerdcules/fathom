import QtQuick
import "."

// A few facts side by side, each a small dim label over its value (the
// weather's feels-like, wind and humidity). Read-only.
Row {
  id: facts
  // [{label, value}]
  property var items: []
  readonly property real column: items.length > 0 ? (width - spacing * (items.length - 1)) / items.length : width
  spacing: 10 * DropSkin.u

  Repeater {
    model: facts.items.length
    delegate: Column {
      required property int index
      readonly property var item: facts.items[index] || ({})
      width: facts.column
      spacing: 2
      DropLabel {
        width: parent.width
        text: item.label || ""
        color: DropSkin.dim
        font.pixelSize: 11 * DropSkin.u
      }
      DropLabel {
        objectName: "fact " + (item.label || "")
        width: parent.width
        text: item.value || ""
        font.pixelSize: 14 * DropSkin.u
        font.weight: Font.DemiBold
      }
    }
  }
}

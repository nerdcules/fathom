import QtQuick
import "."

// A labelled bar that fills from 0 to 1 (how much of the year is gone, a
// quota used): the label on the left, its value in words on the right, the
// bar under them in the accent. A double-click is `doubleClicked`, for a
// meter that opens something on purpose out of the way (the clock's life
// bar).
Item {
  id: meter
  property string label: ""
  property string trail: ""
  property real value: 0
  signal doubleClicked()

  implicitHeight: words.height + 6 * DropSkin.u + bar.height
  height: implicitHeight

  Item {
    id: words
    width: parent.width
    height: labelText.implicitHeight
    DropLabel {
      id: labelText
      anchors.left: parent.left
      width: parent.width - trailText.implicitWidth - 8 * DropSkin.u
      text: meter.label
      color: DropSkin.dim
      font.pixelSize: 12 * DropSkin.u
    }
    DropLabel {
      id: trailText
      anchors.right: parent.right
      text: meter.trail
      color: DropSkin.dim
      font.pixelSize: 12 * DropSkin.u
    }
  }
  Rectangle {
    id: bar
    anchors { left: parent.left; right: parent.right; top: words.bottom; topMargin: 6 * DropSkin.u }
    height: 6 * DropSkin.u
    radius: height / 2
    color: DropSkin.tint(DropSkin.fg, 0.14)
    Rectangle {
      width: Math.max(meter.value > 0 ? height : 0, parent.width * Math.max(0, Math.min(1, meter.value)))
      height: parent.height
      radius: height / 2
      color: DropSkin.accent
    }
  }
  MouseArea {
    anchors.fill: parent
    onDoubleClicked: meter.doubleClicked()
  }
}

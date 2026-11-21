import QtQuick
import "."

// A labelled bar that fills from 0 to 1 (how much of the year is gone, a
// quota used): the label on the left, its value in words on the right, the
// bar under them in the accent (in the urgent colour while `alarm`: a
// limit nearly used up). A double-click is `doubleClicked`, for a
// meter that opens something on purpose out of the way (the clock's life
// bar).
Item {
  id: meter
  property string label: ""
  property string trail: ""
  property real value: 0
  property bool alarm: false
  signal doubleClicked()

  implicitHeight: words.height + 6 * Skin.u + bar.height
  height: implicitHeight

  Item {
    id: words
    width: parent.width
    height: labelText.implicitHeight
    Label {
      id: labelText
      anchors.left: parent.left
      width: parent.width - trailText.implicitWidth - 8 * Skin.u
      text: meter.label
      color: Skin.dim
      font.pixelSize: Skin.text.detail
    }
    Label {
      id: trailText
      anchors.right: parent.right
      text: meter.trail
      color: Skin.dim
      font.pixelSize: Skin.text.detail
    }
  }
  Rectangle {
    id: bar
    anchors { left: parent.left; right: parent.right; top: words.bottom; topMargin: 6 * Skin.u }
    height: 6 * Skin.u
    radius: height / 2
    color: Skin.tint(Skin.fg, 0.14)
    Rectangle {
      width: Math.max(meter.value > 0 ? height : 0, parent.width * Math.max(0, Math.min(1, meter.value)))
      height: parent.height
      radius: height / 2
      color: meter.alarm ? Skin.urgent : Skin.accent
    }
  }
  MouseArea {
    anchors.fill: parent
    onDoubleClicked: meter.doubleClicked()
  }
}

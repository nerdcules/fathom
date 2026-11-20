import QtQuick
import "."

// A glyph, a slider from 0 to 1 and its value in words: the desk's
// SliderRow.qml, which this copies, with `steps` for a slider that stops at
// set places (text size: steps 6 is seven stops). Drag or click the track;
// the arrow keys move one step (5% without steps). The glyph can be a button.
Item {
  id: row
  property string glyph: ""
  property string glyphTip: ""
  property real value: 0
  property string label: ""
  property int steps: 0
  signal moved(real value)
  signal glyphClicked()

  readonly property real step: steps > 0 ? 1 / steps : 0.05
  function snap(v) {
    v = Math.max(0, Math.min(1, v))
    return steps > 0 ? Math.round(v * steps) / steps : v
  }

  height: 34 * DropSkin.u
  opacity: enabled ? 1 : 0.45
  // A stop for the dropdown's arrow keys (DropCard).
  readonly property bool dropStop: true
  Accessible.role: Accessible.Slider
  Accessible.name: glyphTip
  Keys.onLeftPressed: moved(snap(value - step))
  Keys.onRightPressed: moved(snap(value + step))

  Rectangle {
    id: glyphButton
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    width: 32 * DropSkin.u
    height: width
    radius: width / 2
    color: glyphMouse.containsMouse ? DropSkin.tint(DropSkin.fg, 0.12) : "transparent"
    DropLabel {
      anchors.centerIn: parent
      text: row.glyph
      color: DropSkin.accent
      font.pixelSize: 17 * DropSkin.u
    }
    MouseArea {
      id: glyphMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.glyphTip !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: row.glyphClicked()
    }
  }

  Item {
    id: track
    anchors { left: glyphButton.right; leftMargin: 10 * DropSkin.u; right: valueLabel.left; rightMargin: 12 * DropSkin.u; verticalCenter: parent.verticalCenter }
    height: 22 * DropSkin.u

    Rectangle {
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
      height: 6 * DropSkin.u
      radius: height / 2
      color: DropSkin.tint(DropSkin.fg, 0.14)
      Rectangle {
        width: Math.max(height, parent.width * Math.max(0, Math.min(1, row.value)))
        height: parent.height
        radius: height / 2
        color: DropSkin.accent
      }
    }
    Rectangle {
      x: track.width * Math.max(0, Math.min(1, row.value)) - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 16 * DropSkin.u
      height: width
      radius: width / 2
      color: DropSkin.fg
      border.width: row.activeFocus ? 2 : 0
      border.color: DropSkin.accent
    }
    MouseArea {
      objectName: "track"
      anchors.fill: parent
      anchors.margins: -6 * DropSkin.u
      cursorShape: Qt.PointingHandCursor
      function at(x) { return row.snap((x - 6 * DropSkin.u) / track.width) }
      onPressed: function(e) { row.forceActiveFocus(); row.moved(at(e.x)) }
      onPositionChanged: function(e) { if (pressed) row.moved(at(e.x)) }
    }
  }

  DropLabel {
    id: valueLabel
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    width: 64 * DropSkin.u
    horizontalAlignment: Text.AlignRight
    text: row.label
    color: DropSkin.dim
    font.pixelSize: 12 * DropSkin.u
  }
}

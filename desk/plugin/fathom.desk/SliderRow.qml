import QtQuick
import "kit"
import "."

// A glyph, a slider from 0 to 1 and its value in words. Drag or click the
// track; the arrow keys step by 5%. The glyph can be a button (mute).
Item {
  id: row
  property string glyph: ""
  property string glyphTip: ""
  property real value: 0
  property string label: ""
  signal moved(real value)
  signal glyphClicked()

  height: 34 * Skin.u
  opacity: enabled ? 1 : 0.45
  activeFocusOnTab: true
  Keys.onLeftPressed: moved(Math.max(0, value - 0.05))
  Keys.onRightPressed: moved(Math.min(1, value + 0.05))

  Rectangle {
    id: glyphButton
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    width: 32 * Skin.u
    height: width
    radius: width / 2
    color: glyphMouse.containsMouse ? Skin.tint(Skin.fg, 0.12) : "transparent"
    Label {
      anchors.centerIn: parent
      text: row.glyph
      color: Skin.accent
      font.pixelSize: 17 * Skin.u
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
    anchors { left: glyphButton.right; leftMargin: 10 * Skin.u; right: valueLabel.left; rightMargin: 12 * Skin.u; verticalCenter: parent.verticalCenter }
    height: 22 * Skin.u

    Rectangle {
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
      height: 6 * Skin.u
      radius: height / 2
      color: Skin.tint(Skin.fg, 0.14)
      Rectangle {
        width: Math.max(height, parent.width * Math.max(0, Math.min(1, row.value)))
        height: parent.height
        radius: height / 2
        color: Skin.accent
      }
    }
    Rectangle {
      x: track.width * Math.max(0, Math.min(1, row.value)) - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 16 * Skin.u
      height: width
      radius: width / 2
      color: Skin.fg
      border.width: row.activeFocus ? 2 : 0
      border.color: Skin.accent
    }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6 * Skin.u
      cursorShape: Qt.PointingHandCursor
      function at(x) { return Math.max(0, Math.min(1, (x - 6 * Skin.u) / track.width)) }
      onPressed: function(e) { row.forceActiveFocus(); row.moved(at(e.x)) }
      onPositionChanged: function(e) { if (pressed) row.moved(at(e.x)) }
    }
  }

  Label {
    id: valueLabel
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    width: 64 * Skin.u
    horizontalAlignment: Text.AlignRight
    text: row.label
    color: Skin.dim
    font.pixelSize: 12 * Skin.u
  }
}

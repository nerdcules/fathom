import QtQuick
import "."

// One row of a dropdown's list (a display, a network, a machine), styled
// as Quick settings' lists (desk/plugin/fathom.desk/QuickList.qml): a glyph,
// a name and a detail line, lit while `active`. `busy` shows the working
// label on the right instead of `trail`. Clicking anywhere on it is
// `clicked`, unless it isn't `clickable`.
Rectangle {
  id: row
  property string glyph: ""
  property string name: ""
  property string detail: ""
  property string trail: ""
  property bool active: false
  property bool busy: false
  property string busyLabel: ""
  property bool clickable: true
  // Keyboard cursor from the dropdown (its arrow keys), drawn as hover.
  property bool cursor: false
  signal clicked()

  width: parent ? parent.width : 300
  height: 50 * Skin.u
  radius: Skin.corner(12)
  readonly property bool hot: mouse.containsMouse || cursor
  color: Skin.stateFill(Skin.tint(Skin.fg, 0.06), active, hot && (clickable || active), mouse.pressed)
  border.width: 1
  border.color: active ? Skin.selectedEdge : Skin.tint(Skin.fg, 0.1)
  // A stop for the dropdown's arrow keys (DropCard), when it can be used.
  readonly property bool dropStop: clickable
  Accessible.role: Accessible.Button
  Accessible.name: name
  Keys.onReturnPressed: if (clickable) clicked()
  Keys.onEnterPressed: if (clickable) clicked()
  Keys.onSpacePressed: if (clickable) clicked()

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: row.clickable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
  Label {
    id: rowGlyph
    anchors { left: parent.left; leftMargin: 14 * Skin.u; verticalCenter: parent.verticalCenter }
    width: 22 * Skin.u
    text: row.glyph
    color: row.active ? Skin.fg : Skin.accent
    font.pixelSize: 18 * Skin.u
  }
  Column {
    anchors { left: rowGlyph.right; leftMargin: 10 * Skin.u; right: trailLabel.left; rightMargin: 8 * Skin.u; verticalCenter: parent.verticalCenter }
    spacing: 1
    Label {
      width: parent.width
      text: row.name
      font.pixelSize: 13 * Skin.u
      font.weight: Font.DemiBold
    }
    Label {
      width: parent.width
      visible: text !== ""
      text: row.detail
      color: row.active ? Skin.fg : Skin.dim
      font.pixelSize: 11 * Skin.u
    }
  }
  Label {
    id: trailLabel
    anchors { right: parent.right; rightMargin: 14 * Skin.u; verticalCenter: parent.verticalCenter }
    text: row.busy ? row.busyLabel : row.trail
    color: Skin.dim
    font.pixelSize: 11 * Skin.u
  }
  FocusRing {}
}

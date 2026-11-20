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
  height: 50 * DropSkin.u
  radius: 12 * DropSkin.u
  readonly property bool hot: mouse.containsMouse || cursor || activeFocus
  color: active ? DropSkin.tint(DropSkin.accent, mouse.pressed ? 0.55 : (hot ? 0.45 : 0.36))
    : (mouse.pressed ? DropSkin.tint(DropSkin.fg, 0.16) : (hot && clickable ? DropSkin.tint(DropSkin.fg, 0.11) : DropSkin.tint(DropSkin.fg, 0.06)))
  border.width: 1
  border.color: active ? DropSkin.tint(DropSkin.accent, 0.8) : DropSkin.tint(DropSkin.fg, 0.1)
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
  DropLabel {
    id: rowGlyph
    anchors { left: parent.left; leftMargin: 14 * DropSkin.u; verticalCenter: parent.verticalCenter }
    width: 22 * DropSkin.u
    text: row.glyph
    color: row.active ? DropSkin.fg : DropSkin.accent
    font.pixelSize: 18 * DropSkin.u
  }
  Column {
    anchors { left: rowGlyph.right; leftMargin: 10 * DropSkin.u; right: trailLabel.left; rightMargin: 8 * DropSkin.u; verticalCenter: parent.verticalCenter }
    spacing: 1
    DropLabel {
      width: parent.width
      text: row.name
      font.pixelSize: 13 * DropSkin.u
      font.weight: Font.DemiBold
    }
    DropLabel {
      width: parent.width
      visible: text !== ""
      text: row.detail
      color: row.active ? DropSkin.fg : DropSkin.dim
      font.pixelSize: 11 * DropSkin.u
    }
  }
  DropLabel {
    id: trailLabel
    anchors { right: parent.right; rightMargin: 14 * DropSkin.u; verticalCenter: parent.verticalCenter }
    text: row.busy ? row.busyLabel : row.trail
    color: DropSkin.dim
    font.pixelSize: 11 * DropSkin.u
  }
}

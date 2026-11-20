import QtQuick
import "."

// A rounded button with a glyph, a word, or both: the desk's Button.qml,
// which this copies. `primary` lights it, as a chosen option. Works with the
// mouse, and with Return and Space once the dropdown's arrows reach it.
Rectangle {
  id: button
  property string text: ""
  property string glyph: ""
  property bool primary: false
  signal clicked()

  implicitWidth: row.implicitWidth + 22 * DropSkin.u
  implicitHeight: 30 * DropSkin.u
  radius: height / 2
  // A stop for the dropdown's arrow keys (DropCard).
  readonly property bool dropStop: true
  color: primary ? DropSkin.tint(DropSkin.accent, mouse.pressed ? 0.55 : (mouse.containsMouse || activeFocus ? 0.42 : 0.3))
    : (mouse.pressed ? DropSkin.tint(DropSkin.accent, 0.3) : (mouse.containsMouse || activeFocus ? DropSkin.tint(DropSkin.accent, 0.18) : DropSkin.faint))
  border.width: activeFocus ? 1 : 0
  border.color: DropSkin.accent
  Accessible.role: Accessible.Button
  Accessible.name: text
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6 * DropSkin.u
    DropLabel {
      visible: button.glyph !== ""
      text: button.glyph
      color: button.primary ? DropSkin.fg : DropSkin.accent
      font.pixelSize: 13 * DropSkin.u
      anchors.verticalCenter: parent.verticalCenter
    }
    DropLabel {
      visible: button.text !== ""
      text: button.text
      font.pixelSize: 13 * DropSkin.u
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}

import QtQuick
import "."

// A rounded button with a glyph, a word, or both, like the deck's Pill.
// Works with the mouse and with Tab, Return and Space.
Rectangle {
  id: button
  property string text: ""
  property string glyph: ""
  property bool primary: false
  signal clicked()

  implicitWidth: row.implicitWidth + 22 * Skin.u
  implicitHeight: 30 * Skin.u
  radius: height / 2
  activeFocusOnTab: true
  color: primary ? Skin.tint(Skin.accent, mouse.pressed ? 0.55 : (mouse.containsMouse || activeFocus ? 0.42 : 0.3))
    : (mouse.pressed ? Skin.tint(Skin.accent, 0.3) : (mouse.containsMouse || activeFocus ? Skin.tint(Skin.accent, 0.18) : Skin.faint))
  border.width: activeFocus ? 1 : 0
  border.color: Skin.accent
  Accessible.role: Accessible.Button
  Accessible.name: text
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6 * Skin.u
    Label {
      visible: button.glyph !== ""
      text: button.glyph
      color: button.primary ? Skin.fg : Skin.accent
      font.pixelSize: 13 * Skin.u
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      visible: button.text !== ""
      text: button.text
      font.pixelSize: 13 * Skin.u
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

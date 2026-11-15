import QtQuick
import "."

// One Quick settings tile: a glyph, a name and its state; lit when on.
// Click toggles. With `moreable`, a chevron at the side opens the details.
Rectangle {
  id: tile
  property string glyph: ""
  property string title: ""
  property string detail: ""
  property bool on: false
  property bool available: true
  property bool moreable: false
  signal toggled()
  signal more()

  height: 78 * Skin.u
  radius: 14 * Skin.u
  opacity: available ? 1 : 0.45
  color: on ? Skin.tint(Skin.accent, mouse.pressed ? 0.55 : (mouse.containsMouse ? 0.45 : 0.36))
    : (mouse.pressed ? Skin.tint(Skin.fg, 0.16) : (mouse.containsMouse ? Skin.tint(Skin.fg, 0.11) : Skin.tint(Skin.fg, 0.06)))
  border.width: 1
  border.color: on ? Skin.tint(Skin.accent, 0.8) : Skin.tint(Skin.fg, 0.1)
  Behavior on color { ColorAnimation { duration: Skin.ms(120) } }
  Accessible.role: Accessible.CheckBox
  Accessible.name: title
  Accessible.checked: on

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: tile.available
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.toggled()
  }

  Label {
    id: glyphLabel
    anchors { left: parent.left; top: parent.top; margins: 12 * Skin.u }
    text: tile.glyph
    color: tile.on ? Skin.fg : Skin.accent
    font.pixelSize: 19 * Skin.u
  }

  // The chevron for details.
  Rectangle {
    visible: tile.moreable && tile.available
    anchors { right: parent.right; top: parent.top; margins: 6 * Skin.u }
    width: 28 * Skin.u
    height: width
    radius: width / 2
    color: moreMouse.containsMouse ? Skin.tint(Skin.fg, 0.18) : "transparent"
    Label {
      anchors.centerIn: parent
      text: String.fromCodePoint(0xF0142)
      color: tile.on ? Skin.fg : Skin.dim
      font.pixelSize: 15 * Skin.u
    }
    MouseArea {
      id: moreMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.more()
    }
  }

  Column {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 * Skin.u }
    spacing: 1
    Label {
      width: parent.width
      text: tile.title
      font.pixelSize: 13 * Skin.u
      font.weight: Font.DemiBold
    }
    Label {
      width: parent.width
      text: tile.detail
      color: tile.on ? Skin.fg : Skin.dim
      font.pixelSize: 11 * Skin.u
    }
  }
}

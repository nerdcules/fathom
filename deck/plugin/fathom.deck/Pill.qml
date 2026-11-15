import QtQuick
import "."

// A rounded button: a glyph, a word, or both. Works with the mouse and with
// Tab, Return and Space.
Rectangle {
  id: pill
  property string text: ""
  property string glyph: ""
  property string tip: ""
  property bool enabledAction: true
  property bool primary: false
  property bool selected: false
  property color glyphColor: Skin.accent
  signal clicked()

  implicitWidth: pillRow.implicitWidth + 20 * Skin.u
  implicitHeight: 30 * Skin.u
  radius: height / 2
  activeFocusOnTab: enabledAction
  color: {
    if (!enabledAction) return "transparent"
    if (primary) return Skin.tint(Skin.accent, pillMouse.pressed ? 0.55 : (pillMouse.containsMouse || activeFocus ? 0.42 : 0.30))
    if (selected) return Skin.tint(Skin.accent, 0.22)
    if (pillMouse.pressed) return Skin.tint(Skin.accent, 0.30)
    if (pillMouse.containsMouse || activeFocus) return Skin.tint(Skin.accent, 0.18)
    return Skin.faint
  }
  border.width: activeFocus || selected ? 1 : 0
  border.color: Skin.accent
  opacity: enabledAction ? 1 : 0.4
  Accessible.role: Accessible.Button
  Accessible.name: tip || text
  Keys.onReturnPressed: if (enabledAction) clicked()
  Keys.onEnterPressed: if (enabledAction) clicked()
  Keys.onSpacePressed: if (enabledAction) clicked()

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: 6 * Skin.u
    Label {
      visible: pill.glyph !== ""
      text: pill.glyph
      color: pill.primary ? Skin.fg : pill.glyphColor
      font.pixelSize: 13 * Skin.u
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      visible: pill.text !== ""
      text: pill.text
      font.pixelSize: 13 * Skin.u
      font.weight: pill.primary || pill.selected ? Font.DemiBold : Font.Normal
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    id: pillMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: pill.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (pill.enabledAction) pill.clicked()
  }
  Tip { target: pill; text: pill.tip; show: pillMouse.containsMouse && pill.tip !== "" }
}

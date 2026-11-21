import QtQuick
import "."

// Fathom's button (#22): a rounded pill with a glyph, a word, or both. The
// deck, the desk and the bar's dropdowns all use this one. Works with the
// mouse and with Return and Space; Tab reaches it, except in a bar dropdown
// (`tabStop: false`), where Tab moves to the next dropdown and the arrows
// walk the card's stops (DropCard) instead.
Rectangle {
  id: pill
  property string text: ""
  property string glyph: ""
  property string tip: ""
  property bool enabledAction: true
  property bool primary: false
  property bool selected: false
  property bool tabStop: true
  property color glyphColor: Skin.accent
  signal clicked()

  // A stop for a dropdown's arrow keys (DropCard).
  readonly property bool dropStop: !tabStop && enabledAction

  implicitWidth: pillRow.implicitWidth + 20 * Skin.u
  implicitHeight: 30 * Skin.u
  radius: height / 2
  activeFocusOnTab: tabStop && enabledAction
  color: {
    if (!enabledAction) return "transparent"
    if (primary) return Skin.tint(Skin.accent, pillMouse.pressed ? 0.55 : (pillMouse.containsMouse ? 0.42 : 0.30))
    return Skin.stateFill(Skin.faint, selected, pillMouse.containsMouse, pillMouse.pressed)
  }
  // Every usable pill has an edge, so its shape shows when idle (#21); a
  // primary one is filled enough not to need it. Focus is the ring (#16).
  border.width: selected || (enabledAction && !primary) ? 1 : 0
  border.color: selected ? Skin.selectedEdge : Skin.idleEdge
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
      font.pixelSize: Skin.text.body
      anchors.verticalCenter: parent.verticalCenter
    }
    Label {
      visible: pill.text !== ""
      text: pill.text
      font.pixelSize: Skin.text.body
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
  FocusRing {}
  Tip { target: pill; text: pill.tip; show: pillMouse.containsMouse && pill.tip !== "" }
}

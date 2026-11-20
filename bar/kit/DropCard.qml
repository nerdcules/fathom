import QtQuick
import "."

// A Fathom dropdown's card (#14): what fills Omarchy's popup frame
// (KeyboardPanel) under a bar item. The Quick settings glass, a header with
// the item's glyph, title and a line under it, an optional control on the
// right of the header (`trailing`), and the body: whatever the dropdown puts
// inside, in a column.
//
// Keys, as Omarchy's dropdowns take them: Esc closes, Tab and Shift+Tab go
// to the next or previous dropdown on the bar, and the arrows (or h j k l)
// walk the controls; a slider takes Left and Right itself, Return or Space
// presses what has the focus. Nothing shows as chosen until a key is used.
//
// A focus scope, so the keyboard stays with the card if the control that
// had it goes away.
//
// Plain QML with no Omarchy imports, so it renders in tests; DropTheme.qml
// sets its colours from the theme.
FocusScope {
  id: card

  property string title: ""
  property string subtitle: ""
  property string glyph: ""
  property real pad: 18 * DropSkin.u
  default property alias body: bodyColumn.data
  property alias trailing: trailHolder.data
  property alias bodySpacing: bodyColumn.spacing
  // An item's own keys, asked first: a function(event) that returns true
  // for a key it used (the clock's arrows step the month, as Omarchy's do).
  property var keyHandler: null

  signal closeRequested()
  signal tabRequested(int direction)

  implicitHeight: pad * 2 + header.height + 14 * DropSkin.u + bodyColumn.implicitHeight
  focus: true

  // The controls a key can reach, in the order they're drawn: the kit's
  // parts mark themselves (dropStop) rather than joining Qt's Tab chain, so
  // Tab always reaches the card and goes to the next dropdown, as in
  // Omarchy's, whichever control has the keyboard.
  function stops() {
    var out = []
    function collect(item) {
      if (!item || !item.visible) return
      if (item.dropStop === true && item.enabled) out.push(item)
      for (var i = 0; i < item.children.length; i++) collect(item.children[i])
    }
    collect(trailHolder)
    collect(bodyColumn)
    return out
  }
  // Back to nothing chosen, with the keyboard on the card: as a dropdown
  // opens (the scope would otherwise remember the last control).
  function rest() {
    var list = stops()
    for (var i = 0; i < list.length; i++) list[i].focus = false
    card.forceActiveFocus()
  }

  // The next or previous of them, round from the last to the first.
  function walk(forward) {
    var list = stops()
    if (list.length === 0) return
    var at = -1
    for (var i = 0; i < list.length; i++) if (list[i].activeFocus) at = i
    var next = at === -1 ? (forward ? 0 : list.length - 1) : (at + (forward ? 1 : -1) + list.length) % list.length
    list[next].forceActiveFocus()
  }

  Keys.onPressed: function(e) {
    if (typeof card.keyHandler === "function" && card.keyHandler(e)) { e.accepted = true; return }
    var k = e.key
    if (k === Qt.Key_Escape) { card.closeRequested(); e.accepted = true }
    else if (k === Qt.Key_Backtab || (k === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier))) { card.tabRequested(-1); e.accepted = true }
    else if (k === Qt.Key_Tab) { card.tabRequested(1); e.accepted = true }
    else if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Right || k === Qt.Key_L) { card.walk(true); e.accepted = true }
    else if (k === Qt.Key_Up || k === Qt.Key_K || k === Qt.Key_Left || k === Qt.Key_H) { card.walk(false); e.accepted = true }
  }

  // The glass, as Quick settings draws its panel (desk Glass.qml).
  Rectangle {
    id: glass
    anchors.fill: parent
    radius: DropSkin.radius
    color: DropSkin.tint(DropSkin.bg, DropSkin.panelAlpha)
    border.width: 1
    border.color: DropSkin.tint(DropSkin.accent, DropSkin.edgeAlpha)
    clip: true
    Rectangle {
      visible: DropSkin.glow
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
      height: Math.min(90 * DropSkin.u, glass.height - 2)
      radius: glass.radius
      gradient: Gradient {
        GradientStop { position: 0; color: DropSkin.tint(DropSkin.accent, 0.09) }
        GradientStop { position: 1; color: "transparent" }
      }
    }
  }

  Item {
    id: header
    x: card.pad
    y: card.pad
    width: card.width - card.pad * 2
    height: 40 * DropSkin.u

    Rectangle {
      id: badge
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      width: 36 * DropSkin.u
      height: width
      radius: width / 2
      color: DropSkin.tint(DropSkin.accent, 0.18)
      DropLabel {
        anchors.centerIn: parent
        text: card.glyph
        color: DropSkin.accent
        font.pixelSize: 18 * DropSkin.u
      }
    }
    Column {
      anchors { left: badge.right; leftMargin: 12 * DropSkin.u; right: trailHolder.left; rightMargin: 10 * DropSkin.u; verticalCenter: parent.verticalCenter }
      spacing: 1
      DropLabel {
        width: parent.width
        text: card.title
        font.pixelSize: 15 * DropSkin.u
        font.weight: Font.DemiBold
      }
      DropLabel {
        width: parent.width
        visible: text !== ""
        text: card.subtitle
        color: DropSkin.dim
        font.pixelSize: 11 * DropSkin.u
      }
    }
    Item {
      id: trailHolder
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  Column {
    id: bodyColumn
    x: card.pad
    y: header.y + header.height + 14 * DropSkin.u
    width: card.width - card.pad * 2
    spacing: 14 * DropSkin.u
  }
}

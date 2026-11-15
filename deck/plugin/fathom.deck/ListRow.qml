import QtQuick
import QtQuick.Layouts
import "."

// A row in a card's list: a dot, a name with a detail line, and figures on
// the right. Buttons placed inside replace the figures on hover or focus.
Item {
  id: row
  property color tone: Skin.ok
  property bool showDot: true
  property string name: ""
  property string detail: ""
  property color detailColor: Skin.dim
  property string right1: ""
  property string right2: ""
  property bool alwaysShowActions: false
  readonly property bool hovered: rowHover.hovered
  default property alias actions: actionsRow.data
  Layout.fillWidth: true
  implicitHeight: Math.max(40 * Skin.u, texts.implicitHeight + 8 * Skin.u)

  Rectangle {
    anchors.fill: parent
    anchors.margins: -4 * Skin.u
    radius: 10 * Skin.u
    color: rowHover.hovered || actionsRow.activeFocusInside ? Skin.faint : "transparent"
  }
  HoverHandler { id: rowHover }

  Dot {
    id: rowDot
    visible: row.showDot
    tone: row.tone
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }
  Column {
    id: texts
    anchors.left: row.showDot ? rowDot.right : parent.left
    anchors.leftMargin: row.showDot ? 10 * Skin.u : 0
    anchors.right: rightSide.left
    anchors.rightMargin: 8 * Skin.u
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2 * Skin.u
    Label { width: parent.width; text: row.name }
    Label {
      width: parent.width
      text: row.detail
      visible: text !== ""
      color: row.detailColor
      font.pixelSize: 12 * Skin.u
      wrapMode: Text.WordWrap
      maximumLineCount: 3
    }
  }
  Item {
    id: rightSide
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(figures.implicitWidth, actionsRow.implicitWidth)
    height: parent.height
    Column {
      id: figures
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: !actionsRow.showing
      Label { anchors.right: parent.right; text: row.right1; font.pixelSize: 13 * Skin.u }
      Label { anchors.right: parent.right; text: row.right2; visible: text !== ""; color: Skin.dim; font.pixelSize: 12 * Skin.u }
    }
    Row {
      id: actionsRow
      property bool activeFocusInside: {
        for (var i = 0; i < children.length; i++) if (children[i].activeFocus) return true
        return false
      }
      readonly property bool showing: children.length > 0 && (row.alwaysShowActions || rowHover.hovered || activeFocusInside)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4 * Skin.u
      // Hidden until hover, but still reachable with Tab: focusing one
      // shows them all.
      opacity: showing ? 1 : 0
    }
  }
}

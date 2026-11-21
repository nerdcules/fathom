import QtQuick
import "kit"
import QtQuick.Layouts
import "."

// A row in a card's list: a dot, a name with a detail line, and figures on
// the right. Buttons placed inside replace the figures on hover or focus.
Item {
  id: row
  property color tone: Skin.ok
  property bool showDot: true
  // An icon in place of the dot: an image, a glyph, or a name's initial.
  property string iconSource: ""
  property string iconGlyph: ""
  property string iconName: ""
  readonly property bool hasIcon: iconSource !== "" || iconGlyph !== "" || iconName !== ""
  property string name: ""
  property string detail: ""
  property color detailColor: Skin.dim
  property string right1: ""
  property string right2: ""
  property bool alwaysShowActions: false
  // Clickable rows highlight as they would under the keyboard cursor.
  property bool clickable: false
  property bool current: false
  signal clicked()
  readonly property bool hovered: rowHover.hovered
  default property alias actions: actionsRow.data
  Layout.fillWidth: true
  implicitHeight: Math.max(40 * Skin.u, texts.implicitHeight + 8 * Skin.u)

  Rectangle {
    anchors.fill: parent
    anchors.margins: -4 * Skin.u
    radius: 10 * Skin.u
    color: row.current ? Skin.selectedFill
      : (rowHover.hovered || actionsRow.activeFocusInside ? Skin.hoverFill : "transparent")
    border.width: row.current ? 1 : 0
    border.color: Skin.selectedEdge
  }
  HoverHandler { id: rowHover; cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
  // A MouseArea, not a TapHandler: a TapHandler only grabs the press
  // passively, so a click on a row drawn over another (the Start menu's
  // power menu over Recent) clicked the row beneath as well (#13). Declared
  // before the row's buttons so they stay on top of it.
  MouseArea { anchors.fill: parent; enabled: row.clickable; onClicked: row.clicked() }

  AppIcon {
    id: rowIcon
    visible: row.hasIcon
    size: 26 * Skin.u
    source: row.iconSource
    glyph: row.iconGlyph
    name: row.iconName
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }
  Dot {
    id: rowDot
    visible: row.showDot && !row.hasIcon
    tone: row.tone
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }
  Column {
    id: texts
    anchors.left: row.hasIcon ? rowIcon.right : (row.showDot ? rowDot.right : parent.left)
    anchors.leftMargin: row.hasIcon ? 12 * Skin.u : (row.showDot ? 10 * Skin.u : 0)
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

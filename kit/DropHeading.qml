import QtQuick
import "."

// A heading inside a dropdown (an agent's name over its limits): a mark (an
// image, or a glyph when there's none or it doesn't load), the name, a
// second word beside it (a plan), and a dim note on the right.
Item {
  id: heading
  property string icon: ""
  property string glyph: ""
  property string text: ""
  property string detail: ""
  property string trail: ""

  implicitHeight: 26 * Skin.u
  height: implicitHeight

  Image {
    id: mark
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    width: 20 * Skin.u
    height: width
    sourceSize.width: Math.round(width * 2)
    sourceSize.height: Math.round(height * 2)
    fillMode: Image.PreserveAspectFit
    source: heading.icon
    visible: heading.icon !== "" && status === Image.Ready
    asynchronous: true
  }
  Label {
    id: glyphLabel
    anchors.centerIn: mark
    visible: !mark.visible && heading.glyph !== ""
    text: heading.glyph
    color: Skin.accent
    font.pixelSize: Skin.text.large
  }
  Row {
    anchors { left: mark.right; leftMargin: 10 * Skin.u; right: trailLabel.left; rightMargin: 8 * Skin.u; verticalCenter: parent.verticalCenter }
    spacing: 8 * Skin.u
    Label {
      id: name
      text: heading.text
      font.pixelSize: Skin.text.title
      font.weight: Font.DemiBold
      width: Math.min(implicitWidth, parent.width)
    }
    Label {
      anchors.baseline: name.baseline
      text: heading.detail
      color: Skin.dim
      font.pixelSize: Skin.text.detail
      width: Math.max(0, Math.min(implicitWidth, parent.width - name.width - parent.spacing))
    }
  }
  Label {
    id: trailLabel
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    text: heading.trail
    color: Skin.dim
    font.pixelSize: Skin.text.detail
  }
}

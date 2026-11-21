import QtQuick
import "kit"
import QtQuick.Layouts
import "."
import "kit/Format.js" as F

ColumnLayout {
  id: meter
  property string label: ""
  property string value: ""
  property real pct: 0
  property string tone: F.level(pct)
  spacing: 6 * Skin.u
  Layout.fillWidth: true

  RowLayout {
    Layout.fillWidth: true
    Label {
      text: meter.label
      color: Skin.dim
      font.pixelSize: 12 * Skin.u
      font.letterSpacing: 1.2 * Skin.u
      font.capitalization: Font.AllUppercase
    }
    Item { Layout.fillWidth: true }
    Label { text: meter.value; font.pixelSize: 13 * Skin.u }
  }
  Rectangle {
    Layout.fillWidth: true
    height: 6 * Skin.u
    radius: height / 2
    color: Skin.faint
    Rectangle {
      width: parent.width * Math.max(0.01, Math.min(1, meter.pct / 100))
      height: parent.height
      radius: parent.radius
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: meter.tone === "ok" ? Skin.accent : Skin.levelColor(meter.tone) }
        GradientStop { position: 1; color: meter.tone === "ok" ? Skin.violet : Skin.levelColor(meter.tone) }
      }
      Behavior on width { NumberAnimation { duration: 300 * Skin.motion; easing.type: Easing.OutCubic } }
    }
  }
}

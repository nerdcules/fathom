import QtQuick
import "kit"
import QtQuick.Layouts
import "."

Label {
  color: Skin.dim
  font.pixelSize: Skin.text.caption
  font.letterSpacing: 1.4 * Skin.u
  font.capitalization: Font.AllUppercase
  Layout.fillWidth: true
  Layout.topMargin: 4 * Skin.u
}

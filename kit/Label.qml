import QtQuick
import "."

// All of a dropdown's text. Always plain text: names come from apps, networks
// and devices and must never be read as markup.
Text {
  textFormat: Text.PlainText
  color: Skin.fg
  font.family: Skin.fontFamily
  font.pixelSize: Skin.text.label
  elide: Text.ElideRight
}

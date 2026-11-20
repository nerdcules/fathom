import QtQuick
import "."

// All of a dropdown's text. Always plain text: names come from apps, networks
// and devices and must never be read as markup.
Text {
  textFormat: Text.PlainText
  color: DropSkin.fg
  font.family: DropSkin.fontFamily
  font.pixelSize: 14 * DropSkin.u
  elide: Text.ElideRight
}

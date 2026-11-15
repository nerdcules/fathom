import QtQuick
import "."

// All of the desk's text. Always plain text: window titles come from apps
// and web pages and must never be read as markup.
Text {
  textFormat: Text.PlainText
  color: Skin.fg
  font.family: Skin.fontFamily
  font.pixelSize: 14 * Skin.u
  elide: Text.ElideRight
}

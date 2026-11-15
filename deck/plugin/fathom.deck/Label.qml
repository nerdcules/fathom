import QtQuick
import "."

// All of the deck's text. Always plain text: names and messages come from
// the machine and must never be read as markup.
Text {
  textFormat: Text.PlainText
  color: Skin.fg
  font.family: Skin.fontFamily
  font.pixelSize: 14 * Skin.u
  elide: Text.ElideRight
}

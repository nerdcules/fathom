import QtQuick
import "."

Rectangle {
  property color tone: Skin.ok
  width: 8 * Skin.u
  height: width
  radius: width / 2
  color: tone
}

import QtQuick
import "kit"
import QtQuick.Layouts
import "."

// Asks before doing something that can't be undone. Drawn over the whole
// deck; Esc or Cancel backs out.
Item {
  id: confirm
  property string title: ""
  property string body: ""
  property string confirmText: ""
  property bool shown: false
  signal accepted()

  parent: Skin.overlay
  anchors.fill: parent
  z: 200
  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 140 * Skin.motion; easing.type: Easing.OutCubic } }

  function open() { shown = true; cancelButton.forceActiveFocus() }
  function close() { shown = false; if (Skin.overlay) Skin.overlay.forceActiveFocus() }

  Keys.onEscapePressed: function(event) { confirm.close(); event.accepted = true }

  Rectangle {
    anchors.fill: parent
    color: Skin.tint("#000000", 0.45)
    // hoverEnabled: the rows under the dialog don't light up as the pointer
    // passes over them.
    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: confirm.close() }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 64 * Skin.u, 520 * Skin.u)
    height: column.implicitHeight + 48 * Skin.u
    radius: Skin.corner(18)
    color: Skin.tint(Skin.bg, 0.97)
    border.width: 1
    border.color: Skin.tint(Skin.accent, 0.35)
    scale: confirm.shown ? 1 : 0.97
    Behavior on scale { NumberAnimation { duration: 140 * Skin.motion; easing.type: Easing.OutCubic } }
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: 24 * Skin.u
      spacing: 14 * Skin.u
      Label { text: confirm.title; font.pixelSize: 18 * Skin.u; font.weight: Font.DemiBold; Layout.fillWidth: true }
      Label {
        text: confirm.body
        color: Skin.dim
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        Layout.fillWidth: true
      }
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6 * Skin.u
        Item { Layout.fillWidth: true }
        Pill {
          id: cancelButton
          text: Skin.t("cancel")
          onClicked: confirm.close()
          Keys.onEscapePressed: confirm.close()
        }
        Pill {
          text: confirm.confirmText
          primary: true
          onClicked: { confirm.close(); confirm.accepted() }
          Keys.onEscapePressed: confirm.close()
        }
      }
    }
  }
}

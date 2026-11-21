import QtQuick
import "kit"
import "."

// What every view of the deck sits on: it sets the scale for the screen,
// is where tooltips and dialogs draw, and owns the one "are you sure?"
// dialog (Skin.ask). Put DeckView and StartView inside it.
Item {
  id: stage
  default property alias content: holder.data

  readonly property real scaleFactor: Math.max(0.7, Math.min(1.25, Math.min(width / 1600, height / 1000)))
  Binding { target: Skin; property: "u"; value: stage.scaleFactor }
  Binding { target: Skin; property: "overlay"; value: stage }
  Component.onCompleted: {
    Skin.ask = function(title, body, confirmText, onConfirm) {
      dialog.title = title
      dialog.body = body
      dialog.confirmText = confirmText
      dialog.pending = onConfirm
      dialog.open()
    }
  }

  Item {
    id: holder
    anchors.fill: parent
  }

  Confirm {
    id: dialog
    property var pending: null
    onAccepted: if (typeof pending === "function") pending()
  }
}

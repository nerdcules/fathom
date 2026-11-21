import QtQuick
import "."

// A search field with its results under it (the weather's city search).
// The field takes the keyboard as it appears, holding `text` to start
// with. Typing is `edited`; Up and Down move the chosen result (`chose`),
// Return sends the field and the chosen result (`submitted`), Esc drops it
// (`cancelled`), and clicking a result is `picked`. While `busy`, the field
// is locked and shows the working label (after a choice, while it loads).
Column {
  id: search
  property string text: ""
  property string placeholder: ""
  property bool busy: false
  property string busyLabel: ""
  // [{key, name, detail}]
  property var results: []
  property int chosen: 0
  signal edited(string text)
  signal chose(int index)
  signal submitted(string text, int chosen)
  signal cancelled()
  signal picked(string key)

  spacing: 6 * DropSkin.u

  function begin() {
    field.text = search.text
    field.selectAll()
    field.forceActiveFocus()
  }
  Component.onCompleted: Qt.callLater(begin)

  Rectangle {
    width: parent.width
    height: 34 * DropSkin.u
    radius: height / 2
    color: DropSkin.tint(DropSkin.fg, 0.06)
    border.width: 1
    border.color: field.activeFocus ? DropSkin.accent : DropSkin.tint(DropSkin.fg, 0.18)
    TextInput {
      id: field
      objectName: "search field"
      anchors { fill: parent; leftMargin: 14 * DropSkin.u; rightMargin: 14 * DropSkin.u }
      verticalAlignment: TextInput.AlignVCenter
      enabled: !search.busy
      color: DropSkin.fg
      font.family: DropSkin.fontFamily
      font.pixelSize: 13 * DropSkin.u
      clip: true
      Accessible.name: search.placeholder
      onTextEdited: search.edited(text)
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) { search.cancelled(); e.accepted = true }
        else if (e.key === Qt.Key_Down) { if (search.chosen < search.results.length - 1) search.chose(search.chosen + 1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { if (search.chosen > 0) search.chose(search.chosen - 1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { search.submitted(field.text, search.chosen); e.accepted = true }
        else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) e.accepted = true
      }
      DropLabel {
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text === "" || search.busy
        anchors.right: search.busy ? parent.right : undefined
        text: search.busy ? search.busyLabel : search.placeholder
        color: DropSkin.dim
        font.pixelSize: 13 * DropSkin.u
      }
    }
  }

  Repeater {
    model: search.results.length
    delegate: DropRow {
      required property int index
      readonly property var result: search.results[index] || ({})
      objectName: "result " + (result.key || index)
      width: search.width
      height: 44 * DropSkin.u
      name: result.name || ""
      detail: result.detail || ""
      cursor: index === search.chosen
      onClicked: search.picked(String(result.key))
    }
  }
}

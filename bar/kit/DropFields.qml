import QtQuick
import "."

// A row of short text fields and their labels, for a value or two typed in
// place (the clock's birth year and life expectancy). The first takes the
// keyboard as it appears. Return (or OK) sends what was typed, Esc (or
// Cancel) drops it, and Tab hops between the fields, so none of those keys
// reach the dropdown while they're up.
Column {
  id: form
  // [{key, label, value, placeholder, digits}]
  property var fields: []
  property string okLabel: ""
  property string cancelLabel: ""
  signal submitted(var values)
  signal cancelled()

  spacing: 8 * DropSkin.u

  function values() {
    var out = {}
    for (var i = 0; i < inputs.count; i++) {
      var input = inputs.itemAt(i)
      if (input) out[input.key] = input.field.text
    }
    return out
  }
  function hop(from, step) {
    var n = inputs.count
    if (n === 0) return
    var next = inputs.itemAt((from + step + n) % n)
    if (next) { next.field.selectAll(); next.field.forceActiveFocus() }
  }
  function keys(e, index) {
    if (e.key === Qt.Key_Escape) { form.cancelled(); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { form.submitted(form.values()); e.accepted = true }
    else if (e.key === Qt.Key_Tab) { form.hop(index, 1); e.accepted = true }
    else if (e.key === Qt.Key_Backtab) { form.hop(index, -1); e.accepted = true }
  }

  Component.onCompleted: Qt.callLater(function() { form.hop(-1, 1) })
  onVisibleChanged: if (visible) Qt.callLater(function() { form.hop(-1, 1) })

  Flow {
    width: parent.width
    spacing: 10 * DropSkin.u
    Repeater {
      id: inputs
      model: form.fields.length
      delegate: Row {
        required property int index
        readonly property var spec: form.fields[index] || ({})
        readonly property string key: String(spec.key || "")
        property alias field: input
        spacing: 8 * DropSkin.u
        DropLabel {
          anchors.verticalCenter: parent.verticalCenter
          text: spec.label || ""
          color: DropSkin.dim
          font.pixelSize: 12 * DropSkin.u
        }
        Rectangle {
          width: 80 * DropSkin.u
          height: 30 * DropSkin.u
          radius: height / 2
          color: DropSkin.tint(DropSkin.fg, 0.06)
          border.width: 1
          border.color: input.activeFocus ? DropSkin.accent : DropSkin.tint(DropSkin.fg, 0.18)
          TextInput {
            id: input
            objectName: "field " + parent.parent.key
            anchors { fill: parent; leftMargin: 12 * DropSkin.u; rightMargin: 12 * DropSkin.u }
            verticalAlignment: TextInput.AlignVCenter
            text: spec.value !== undefined && spec.value !== null ? String(spec.value) : ""
            color: DropSkin.fg
            font.family: DropSkin.fontFamily
            font.pixelSize: 13 * DropSkin.u
            clip: true
            inputMethodHints: spec.digits ? Qt.ImhDigitsOnly : Qt.ImhNone
            validator: spec.digits ? digitsOnly : null
            Accessible.name: spec.label || ""
            Keys.onPressed: function(e) { form.keys(e, index) }
            DropLabel {
              anchors.verticalCenter: parent.verticalCenter
              visible: input.text === ""
              text: spec.placeholder || ""
              color: DropSkin.dim
              font.pixelSize: 13 * DropSkin.u
            }
          }
        }
      }
    }
  }
  RegularExpressionValidator { id: digitsOnly; regularExpression: /[0-9]{0,4}/ }

  Row {
    spacing: 8 * DropSkin.u
    DropButton {
      objectName: "fields ok"
      primary: true
      text: form.okLabel
      onClicked: form.submitted(form.values())
    }
    DropButton {
      objectName: "fields cancel"
      text: form.cancelLabel
      onClicked: form.cancelled()
    }
  }
}

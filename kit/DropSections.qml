import QtQuick
import "."

// The factory's renderer (#14): draws a dropdown's body from a description,
// so a new bar item needs a list of sections, not a new screen. Each
// section is an object with a `type`:
//
//   slider   {key, glyph, tip, value (0..1), label, steps}      -> moved(key, value)
//   choices  {key, title, options: [{value, label}], chosen}    -> picked(key, value)
//   rows     {key, title, rows: [{key, glyph, name, detail,
//             trail, active, busy, clickable}], busyLabel}      -> picked(key, row key)
//   switch   {key, glyph, name, detail, on}                     -> toggled(key, !on)
//   actions  {key, buttons: [{key, label, glyph, primary}]}     -> picked(key, button key)
//   meter    {key, label, trail, value (0..1), alarm}           -> picked(key, "doubleClick")
//   heading  {key, icon (image URL), glyph, text, detail, trail}
//   fields   {key, fields: [{key, label, value, placeholder,
//             digits}], okLabel, cancelLabel}                   -> submitted(key, {field: text}),
//                                                                  cancelled(key)
//   facts    {items: [{label, value}]}
//   strip    {key, items: [{key, glyph, name, detail}]}
//   search   {key, text, placeholder, busy, busyLabel, autoFocus,
//             results: [{key, glyph, name, detail}], chosen}           -> edited(key, text), moved(key, chosen
//                                                                  index), submitted(key, {text,
//                                                                  chosen}), cancelled(key),
//                                                                  picked(key, result key)
//   text     {text, dim}
//
// `hidden: true` leaves a section out. Every part is the kit's, in the Quick
// settings look, and every control can be reached with the keys (DropCard).
Column {
  id: sections
  property var model: []
  signal moved(string key, real value)
  signal picked(string key, string value)
  signal toggled(string key, bool on)
  signal submitted(string key, var values)
  signal cancelled(string key)
  signal edited(string key, string text)

  spacing: 14 * Skin.u

  // Counted, not handed the list: a new description (every value change
  // makes one) then updates the parts in place instead of building them
  // again, so the control with the keyboard or under a drag keeps it (seen
  // in the test VM: a text size change lost the keyboard). Inner lists are
  // counted the same way.
  Repeater {
    model: Array.isArray(sections.model) ? sections.model.length : 0
    delegate: Loader {
      id: slot
      required property int index
      readonly property var spec: sections.model[index] || ({})
      width: sections.width
      visible: !spec.hidden
      active: !spec.hidden
      sourceComponent: ({ slider: sliderPart, choices: choicesPart, rows: rowsPart, "switch": switchPart,
                          actions: actionsPart, text: textPart, meter: meterPart, fields: fieldsPart,
                          facts: factsPart, strip: stripPart, search: searchPart, heading: headingPart })[spec.type] || null
    }
  }

  Component {
    id: sliderPart
    DropSlider {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      glyph: spec.glyph || ""
      glyphTip: spec.tip || ""
      value: Number(spec.value) || 0
      label: spec.label || ""
      steps: spec.steps || 0
      onMoved: function(v) { sections.moved(spec.key, v) }
    }
  }

  Component {
    id: choicesPart
    Column {
      property var spec: parent ? parent.spec : ({})
      width: sections.width
      spacing: 8 * Skin.u
      Label {
        visible: text !== ""
        text: spec.title || ""
        color: Skin.dim
        font.pixelSize: Skin.text.detail
      }
      Flow {
        width: parent.width
        spacing: 8 * Skin.u
        Repeater {
          model: (spec.options || []).length
          delegate: Pill {
            tabStop: false
            required property int index
            readonly property var modelData: spec.options[index] || ({})
            objectName: spec.key + " " + modelData.value
            text: modelData.label
            primary: String(modelData.value) === String(spec.chosen)
            Accessible.checked: primary
            onClicked: sections.picked(spec.key, String(modelData.value))
          }
        }
      }
    }
  }

  Component {
    id: rowsPart
    Column {
      property var spec: parent ? parent.spec : ({})
      width: sections.width
      spacing: 6 * Skin.u
      Label {
        visible: text !== ""
        text: spec.title || ""
        color: Skin.dim
        font.pixelSize: Skin.text.detail
      }
      Repeater {
        model: (spec.rows || []).length
        delegate: DropRow {
          required property int index
          readonly property var modelData: spec.rows[index] || ({})
          objectName: spec.key + " " + modelData.key
          glyph: modelData.glyph || ""
          name: modelData.name || ""
          detail: modelData.detail || ""
          trail: modelData.trail || ""
          active: modelData.active === true
          busy: modelData.busy === true
          busyLabel: spec.busyLabel || ""
          clickable: modelData.clickable !== false
          onClicked: sections.picked(spec.key, String(modelData.key))
        }
      }
    }
  }

  Component {
    id: switchPart
    DropRow {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      glyph: spec.glyph || ""
      name: spec.name || ""
      detail: spec.detail || ""
      trail: spec.on ? Skin.t("drop.on") : Skin.t("drop.off")
      active: spec.on === true
      Accessible.role: Accessible.CheckBox
      Accessible.checked: spec.on === true
      onClicked: sections.toggled(spec.key, !(spec.on === true))
    }
  }

  Component {
    id: actionsPart
    Flow {
      property var spec: parent ? parent.spec : ({})
      width: sections.width
      spacing: 8 * Skin.u
      Repeater {
        model: (spec.buttons || []).length
        delegate: Pill {
          tabStop: false
          required property int index
          readonly property var modelData: spec.buttons[index] || ({})
          objectName: spec.key + " " + modelData.key
          text: modelData.label || ""
          glyph: modelData.glyph || ""
          primary: modelData.primary === true
          onClicked: sections.picked(spec.key, String(modelData.key))
        }
      }
    }
  }

  Component {
    id: headingPart
    DropHeading {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key || ""
      width: sections.width
      icon: spec.icon || ""
      glyph: spec.glyph || ""
      text: spec.text || ""
      detail: spec.detail || ""
      trail: spec.trail || ""
    }
  }

  Component {
    id: meterPart
    DropMeter {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      label: spec.label || ""
      trail: spec.trail || ""
      value: Number(spec.value) || 0
      alarm: spec.alarm === true
      onDoubleClicked: sections.picked(spec.key, "doubleClick")
    }
  }

  Component {
    id: fieldsPart
    DropFields {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      fields: spec.fields || []
      okLabel: spec.okLabel || ""
      cancelLabel: spec.cancelLabel || ""
      onSubmitted: function(values) { sections.submitted(spec.key, values) }
      onCancelled: sections.cancelled(spec.key)
    }
  }

  Component {
    id: factsPart
    DropFacts {
      property var spec: parent ? parent.spec : ({})
      width: sections.width
      items: spec.items || []
    }
  }

  Component {
    id: stripPart
    DropStrip {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      items: spec.items || []
    }
  }

  Component {
    id: searchPart
    DropSearch {
      property var spec: parent ? parent.spec : ({})
      objectName: spec.key
      width: sections.width
      text: spec.text || ""
      placeholder: spec.placeholder || ""
      busy: spec.busy === true
      busyLabel: spec.busyLabel || ""
      results: spec.results || []
      chosen: Number(spec.chosen) || 0
      autoFocus: spec.autoFocus !== false
      onEdited: function(t) { sections.edited(spec.key, t) }
      onChose: function(i) { sections.moved(spec.key, i) }
      onSubmitted: function(t, i) { sections.submitted(spec.key, { text: t, chosen: i }) }
      onCancelled: sections.cancelled(spec.key)
      onPicked: function(k) { sections.picked(spec.key, k) }
    }
  }

  Component {
    id: textPart
    Label {
      property var spec: parent ? parent.spec : ({})
      width: sections.width
      text: spec.text || ""
      color: spec.dim ? Skin.dim : Skin.fg
      wrapMode: Text.WordWrap
      font.pixelSize: Skin.text.detail
    }
  }
}

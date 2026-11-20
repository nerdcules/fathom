import QtQuick
import QtTest
import "kit"

// The bar dropdowns' factory (#14), with real clicks and keys: a card drawn
// from a description, as every Fathom dropdown is. Sliders send where they
// were clicked (a stepped one, a stop), choices send their value and light
// the chosen one, rows and buttons send their key, a row that can't be used
// sends nothing, a switch sends its new state, hidden sections aren't drawn,
// and the keys work as Omarchy's dropdowns do. Run by tests/test_bar.py with
// the kit beside it, as install.sh puts it.
Item {
  id: top
  width: 480
  height: 900
  property var log: []

  readonly property var spec: [
    { type: "slider", key: "level", glyph: "L", tip: "Level", value: 0.4, label: "40%" },
    { type: "slider", key: "stops", glyph: "S", tip: "Stops", steps: 6, value: 4 / 6, label: "14 px" },
    { type: "slider", key: "gone", hidden: true, value: 0 },
    { type: "choices", key: "scale", title: "Scale", chosen: "1.25",
      options: [{ value: "1", label: "1×" }, { value: "1.25", label: "1.25×" }, { value: "2", label: "2×" }] },
    { type: "switch", key: "night", glyph: "N", name: "Night light", on: false },
    { type: "rows", key: "screens", title: "Displays", rows: [
      { key: "eDP-1", name: "eDP-1", active: true, clickable: false },
      { key: "HDMI-A-1", name: "HDMI-A-1", active: true } ] },
    { type: "actions", key: "do", buttons: [{ key: "settings", label: "Settings" }] },
    { type: "text", text: "A note", dim: true },
    { type: "meter", key: "year", label: "2026", trail: "88%", value: 0.88 },
    { type: "fields", key: "life", okLabel: "Save", cancelLabel: "Cancel", hidden: true,
      fields: [{ key: "born", label: "Born", value: "", digits: true }, { key: "to", label: "Live to", value: "90", digits: true }] }
  ]

  DropCard {
    id: card
    x: 20; y: 20; width: 400
    title: "Display"
    property bool claimX: false
    keyHandler: function(e) { if (card.claimX && e.key === Qt.Key_X) { top.log.push("x"); return true } return false }
    onCloseRequested: top.log.push("close")
    onTabRequested: function(d) { top.log.push("tab " + d) }
    DropSections {
      id: sections
      width: parent.width
      model: top.spec
      onMoved: function(k, v) { top.log.push(k + " " + Math.round(v * 100)) }
      onPicked: function(k, v) { top.log.push(k + " " + v) }
      onToggled: function(k, on) { top.log.push(k + " " + on) }
      onSubmitted: function(k, v) { top.log.push(k + " " + JSON.stringify(v)) }
      onCancelled: function(k) { top.log.push(k + " cancelled") }
    }
  }

  function find(name) {
    function walk(item) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) { var f = walk(item.children[i]); if (f) return f }
      return null
    }
    return walk(card)
  }
  function trackOf(slider) {
    for (var i = 0; i < slider.children.length; i++) {
      var c = slider.children[i]
      for (var j = 0; j < c.children.length; j++) if (c.children[j].objectName === "track") return c.children[j]
    }
    return null
  }
  function click(item) {
    var p = item.mapToItem(top, item.width / 2, item.height / 2)
    tc.mouseClick(top, p.x, p.y)
    tc.wait(30)
  }

  TestCase {
    id: tc
    name: "DropSections"
    when: windowShown

    function init() {
      top.log = []
      card.rest()
      wait(30)
    }

    function test_a_slider_sends_where_it_was_clicked() {
      var track = trackOf(find("level"))
      var p = track.mapToItem(top, track.width * 0.75, track.height / 2)
      mouseClick(top, p.x, p.y)
      compare(top.log.length, 1)
      var got = Number(top.log[0].split(" ")[1])
      verify(got >= 72 && got <= 78, "about 75: " + got)
    }

    // A click near the far end of a stepped slider lands on the last stop.
    function test_a_stepped_slider_stops_at_a_stop() {
      var track = trackOf(find("stops"))
      var p = track.mapToItem(top, track.width - 2, track.height / 2)
      mouseClick(top, p.x, p.y)
      compare(top.log, ["stops 100"])
    }

    function test_hidden_sections_are_not_drawn() {
      verify(!find("gone"), "no hidden slider")
    }

    function test_choices() {
      verify(find("scale 1.25").primary, "the chosen one is lit")
      verify(!find("scale 2").primary)
      click(find("scale 2"))
      compare(top.log, ["scale 2"])
    }

    function test_rows_and_buttons_send_their_key() {
      click(find("screens HDMI-A-1"))
      click(find("screens eDP-1"))
      click(find("do settings"))
      compare(top.log, ["screens HDMI-A-1", "do settings"], "a row that can't be used sends nothing")
    }

    function test_a_switch_sends_its_new_state() {
      click(find("night"))
      compare(top.log, ["night true"])
    }

    // Every value change hands over a new description; the parts stay and
    // the one with the keyboard keeps it.
    function test_a_new_description_updates_in_place() {
      var slider = find("stops")
      slider.forceActiveFocus()
      var copy = top.spec.map(function(x) { var c = {}; for (var k in x) c[k] = x[k]; return c })
      copy[1].value = 5 / 6
      copy[1].label = "16 px"
      copy[3].chosen = "2"
      sections.model = copy
      wait(30)
      verify(find("stops") === slider, "the same slider")
      verify(slider.activeFocus, "it keeps the keyboard")
      compare(slider.value, 5 / 6)
      verify(find("scale 2").primary, "the new choice is lit")
      sections.model = Qt.binding(function() { return top.spec })
    }

    function test_a_meter_shows_its_value_and_sends_a_double_click() {
      var meter = find("year")
      verify(meter.visible)
      compare(meter.value, 0.88)
      var p = meter.mapToItem(top, meter.width / 2, meter.height / 2)
      mouseDoubleClickSequence(top, p.x, p.y)
      compare(top.log, ["year doubleClick"])
    }

    function test_fields_take_typing_and_send_it() {
      var copy = top.spec.map(function(x) { var c = {}; for (var k in x) c[k] = x[k]; return c })
      copy[9].hidden = false
      sections.model = copy
      wait(80)
      var born = find("field born")
      verify(born, "a field for each")
      verify(born.activeFocus, "the first takes the keyboard")
      keyClick("1"); keyClick("9"); keyClick("x"); keyClick("8"); keyClick("0")
      compare(born.text, "1980", "digits only")
      keyClick(Qt.Key_Tab)
      verify(find("field to").activeFocus, "Tab hops to the next field, not the next dropdown")
      keyClick(Qt.Key_Return)
      compare(top.log, ['life {"born":"1980","to":"90"}'])
      keyClick(Qt.Key_Escape)
      compare(top.log[1], "life cancelled", "Esc cancels, it doesn't close the dropdown")
      sections.model = Qt.binding(function() { return top.spec })
    }

    function test_an_item_can_claim_keys_first() {
      card.claimX = true
      keyClick(Qt.Key_X)
      keyClick(Qt.Key_Escape)
      compare(top.log, ["x", "close"], "claimed first; the rest as before")
      card.claimX = false
    }

    function test_keys() {
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      compare(top.log, ["close", "tab 1", "tab -1"])
      // Down reaches the first slider; Right turns it up a step (5%).
      card.rest()
      keyClick(Qt.Key_Down)
      verify(find("level").activeFocus, "Down goes to the first control")
      keyClick(Qt.Key_Right)
      compare(top.log[3], "level 45")
      // On through the stepped slider to the choices; Right walks them and
      // Return presses one.
      keyClick(Qt.Key_Down)
      verify(find("stops").activeFocus)
      keyClick(Qt.Key_Down)
      verify(find("scale 1").activeFocus)
      keyClick(Qt.Key_Right)
      verify(find("scale 1.25").activeFocus, "Right walks the buttons")
      keyClick(Qt.Key_Return)
      compare(top.log[4], "scale 1.25")
      // Up from nothing chosen goes to the last control.
      card.rest()
      keyClick(Qt.Key_Up)
      verify(find("do settings").activeFocus, "Up goes to the last button")
      keyClick(Qt.Key_Down)
      verify(find("level").activeFocus, "Down from the last wraps to the first")
    }
  }
}

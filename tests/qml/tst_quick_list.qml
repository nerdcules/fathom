import QtQuick
import QtTest
import "../../desk/plugin/fathom.desk"
import "../../desk/plugin/fathom.desk/kit"

// Quick settings' list page (#14) with real clicks and keys: a row click
// sends its key, a header row sends nothing, the password field sends what
// was typed on Enter or Connect, Esc cancels it, and back goes back.
// Run by tests/test_start_clicks.py.
Item {
  id: top
  width: 500
  height: 700
  property var log: []

  QuickList {
    id: list
    x: 20; y: 20; width: 420
    title: "Wi-Fi"
    on: true
    connectLabel: "Connect"
    cancelLabel: "Cancel"
    rows: [
      { header: "Saved" },
      { key: "Home", glyph: "", name: "Home", detail: "Connected", active: true },
      { key: "Cafe", glyph: "", name: "Cafe", detail: "Secured", ask: false },
      { key: "Library", glyph: "", name: "Library", detail: "Open" }
    ]
    onBack: top.log.push("back")
    onToggled: top.log.push("toggled")
    onPicked: function(key) { top.log.push("picked " + key) }
    onPasswordGiven: function(key, password) { top.log.push("password " + key + " " + password) }
    onAskCancelled: top.log.push("cancel")
  }

  // A tile (#15): Space toggles it, Right opens its list.
  QuickTile {
    id: tile
    x: 20; y: 600; width: 140
    title: "Wi-Fi"
    moreable: true
    onToggled: top.log.push("tile toggled")
    onMore: top.log.push("tile more")
  }

  function all(item, pred, out) {
    out = out || []
    if (pred(item)) out.push(item)
    for (var i = 0; i < item.children.length; i++) all(item.children[i], pred, out)
    return out
  }
  function labelled(text) {
    return all(list, function(i) { return i.text === text && i.visible && i.hasOwnProperty("textFormat") })[0]
  }
  function click(item) {
    var p = item.mapToItem(top, item.width / 2, item.height / 2)
    tc.mouseClick(top, p.x, p.y)
    tc.wait(50)
  }

  TestCase {
    id: tc
    name: "QuickList"
    when: windowShown

    function init() {
      top.log = []
      list.rows = list.rows.map(function(r) { var c = {}; for (var k in r) c[k] = r[k]; c.ask = false; return c })
      wait(50)
    }

    function test_a_row_click_sends_its_key() {
      click(labelled("Cafe"))
      compare(top.log, ["picked Cafe"])
      click(labelled("Library"))
      compare(top.log, ["picked Cafe", "picked Library"])
    }

    function test_a_header_sends_nothing() {
      click(labelled("Saved"))
      compare(top.log, [])
    }

    function test_back_and_the_switch() {
      var buttons = all(list, function(i) { return i.hasOwnProperty("primary") && i.visible })
      click(buttons[0])
      compare(top.log, ["back"])
      click(buttons[1])
      compare(top.log, ["back", "toggled"])
    }

    function test_the_password_field() {
      list.rows = list.rows.map(function(r) { var c = {}; for (var k in r) c[k] = r[k]; c.ask = r.key === "Cafe"; return c })
      wait(50)
      var field = all(list, function(i) { return i.objectName === "password" && i.visible })[0]
      verify(field, "a password field under Cafe")
      verify(field.activeFocus, "it takes the keys at once")
      keyClick("s"); keyClick("e"); keyClick("c")
      keyClick(Qt.Key_Return)
      compare(top.log, ["password Cafe sec"])
      click(labelled("Connect"))
      compare(top.log, ["password Cafe sec", "password Cafe sec"])
      field.forceActiveFocus()
      keyClick(Qt.Key_Escape)
      compare(top.log, ["password Cafe sec", "password Cafe sec", "cancel"])
      click(labelled("Cancel"))
      compare(top.log[3], "cancel")
    }

    function test_keys_reach_the_rows_and_the_tiles() {
      // #15: a row takes Tab focus and Space or Return picks it; a tile
      // toggles on Space and Return and opens its list on Right.
      var rows = all(list, function(i) { return i.activeFocusOnTab === true && i.visible && i.hasOwnProperty("radius") && i.height > 40 })
      verify(rows.length >= 3, "the rows take Tab")
      rows[1].forceActiveFocus()
      keyClick(Qt.Key_Return)
      rows[2].forceActiveFocus()
      keyClick(Qt.Key_Space)
      tile.forceActiveFocus()
      keyClick(Qt.Key_Space)
      keyClick(Qt.Key_Right)
      compare(top.log, ["picked Cafe", "picked Library", "tile toggled", "tile more"])
      verify(tile.activeFocusOnTab)
      rows[0].forceActiveFocus()
      tile.available = false
      verify(!tile.activeFocusOnTab, "an unavailable tile isn't a stop")
      tile.available = true
    }

    function test_no_rows_shows_the_empty_text() {
      var keep = list.rows
      list.emptyText = "Looking…"
      list.rows = []
      wait(50)
      verify(labelled("Looking…"), "the empty text shows")
      list.rows = keep
      list.emptyText = ""
    }
  }
}

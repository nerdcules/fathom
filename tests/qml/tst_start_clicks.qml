import QtQuick
import QtTest
import "../../deck/plugin/fathom.deck"

// The Start menu with real mouse clicks: a click lands on what is on top and
// nothing under it (#13: Restart in the power menu also opened the Recent
// project beneath it), and rows under a menu or dialog don't light up as the
// pointer passes over it. Run by tests/test_start_clicks.py.
Item {
  id: top
  width: 1400
  height: 900
  property var log: []

  StartView {
    id: sv
    anchors.fill: parent
    apps: ["code", "whatsapp", "files", "chromium", "ghostty", "obsidian"].map(function(id) {
      return { id: id, name: id, comment: "", icon: "", keywords: "" }
    })
    menu: ({
      home: "/home/u",
      status: null,
      projects: [1, 2, 3, 4, 5].map(function(i) { return { name: "proj" + i, path: "/home/u/Work/proj" + i, when: 0, tech: [] } }),
      config: { pinned: ["code", "whatsapp", "files", "chromium", "ghostty", "obsidian"], suggestions: [] }
    })
    onLaunchApp: function(id) { top.log.push("launchApp " + id) }
    onOpenProject: function(how, path) { top.log.push("openProject " + how + " " + path) }
    onOpenPage: function(page) { top.log.push("openPage " + page) }
    onAskRequested: function(text, path) { top.log.push("ask " + text) }
    onActionRequested: function(id) { top.log.push("action " + id) }
    onPinRequested: function(id, pin) { top.log.push("pin " + id) }
    onCloseRequested: top.log.push("close")
  }

  // A row with a Confirm dialog over it, in its own corner of the window.
  Item {
    id: confirmStage
    x: 0; y: 0; width: 400; height: 300
    visible: false
    ListRow { id: underDialog; x: 0; y: 130; width: 400; clickable: true; name: "under the dialog" }
    Confirm { id: dialog; parent: confirmStage }
  }

  function all(item, pred, out) {
    out = out || []
    if (pred(item)) out.push(item)
    for (var i = 0; i < item.children.length; i++) all(item.children[i], pred, out)
    return out
  }
  function isRow(i) { return i.hasOwnProperty("clickable") && i.hasOwnProperty("showDot") && i.visible }
  function click(item) {
    var p = item.mapToItem(top, item.width / 2, item.height / 2)
    tc.mouseClick(top, p.x, p.y)
    tc.wait(50)
  }

  TestCase {
    id: tc
    name: "StartClicks"
    when: windowShown

    property var powerMenu: null

    function init() {
      top.log = []
      powerMenu = all(sv, function(i) { return i.z === 50 })[0]
      verify(powerMenu, "the power menu")
    }

    // Put everything back even when a test fails half way.
    function cleanup() {
      dialog.shown = false
      confirmStage.visible = false
      all(sv, function(i) { return i.z === 60 })[0].visible = false
      sv.visible = true
      sv.closePowerMenu()
      mouseMove(top, 1, 1)
      wait(50)
    }

    function powerRows() {
      return all(powerMenu, isRow)
    }

    function test_esc_closes_start_wherever_the_keyboard_is() {
      // Tab moves the keyboard off the search field onto a button; Esc
      // still closes Start.
      var pills = all(sv, function(i) { return i.activeFocusOnTab === true && i.visible && i.hasOwnProperty("tabStop") })
      verify(pills.length > 0, "Start has buttons that take Tab")
      pills[0].forceActiveFocus()
      keyClick(Qt.Key_Escape)
      compare(top.log, ["close"])
    }

    function test_power_rows_click_nothing_beneath_data() {
      return sv.powerIds.map(function(id, i) { return { tag: id, index: i, id: id } })
    }

    function test_power_rows_click_nothing_beneath(data) {
      sv.openPowerMenu()
      wait(50)
      var rows = powerRows()
      compare(rows.length, sv.powerIds.length)
      click(rows[data.index])
      var confirm = sv.actionFor(data.id).confirm === true
      if (!confirm) {
        compare(top.log, ["action " + data.id])
        return
      }
      // Sign out, Restart and Shut down ask first; nothing is sent yet.
      compare(sv.powerAsk, data.id)
      compare(top.log, [])
      var yes = all(powerMenu, function(i) { return i.hasOwnProperty("primary") && i.primary && i.visible })[0]
      verify(yes, "the yes button")
      click(yes)
      compare(top.log, ["action " + data.id])
      verify(!powerMenu.visible)
    }

    function hoveredRecent() {
      return all(sv, function(i) { return isRow(i) && i.hovered && /^proj/.test(i.name) })
        .map(function(r) { return r.name })
    }

    function test_power_menu_keeps_hover_to_itself() {
      sv.openPowerMenu()
      wait(50)
      var rows = powerRows()
      for (var i = 0; i < rows.length; i++) {
        var p = rows[i].mapToItem(top, rows[i].width / 2, rows[i].height / 2)
        mouseMove(top, p.x, p.y)
        wait(50)
        verify(rows[i].hovered, sv.powerIds[i] + " lights up under the pointer")
        compare(hoveredRecent(), [], "nothing under " + sv.powerIds[i] + " lights up")
      }
      // Outside the menu, over Recent: the backdrop takes it.
      var proj1 = all(sv, function(r) { return isRow(r) && r.name === "proj1" })[0]
      var q = proj1.mapToItem(top, 20, proj1.height / 2)
      mouseMove(top, q.x, q.y)
      wait(50)
      compare(hoveredRecent(), [])
      sv.closePowerMenu()
      mouseMove(top, q.x, q.y + 1)
      wait(50)
      compare(hoveredRecent(), ["proj1"], "with the menu closed, Recent lights up again")
    }

    function test_about_card_keeps_hover_to_itself() {
      var about = all(sv, function(i) { return i.z === 60 })[0]
      verify(about, "the About card")
      about.visible = true
      var proj1 = all(sv, function(r) { return isRow(r) && r.name === "proj1" })[0]
      var q = proj1.mapToItem(top, 20, proj1.height / 2)
      mouseMove(top, q.x, q.y)
      wait(50)
      compare(hoveredRecent(), [])
    }

    function test_confirm_keeps_hover_to_itself() {
      sv.visible = false
      confirmStage.visible = true
      mouseMove(top, 20, 150)
      wait(50)
      verify(underDialog.hovered, "the row lights up with no dialog")
      dialog.shown = true
      wait(300)
      mouseMove(top, 20, 151)
      wait(50)
      verify(!underDialog.hovered, "the row under the dialog's backdrop stays dark")
      mouseMove(top, 200, 150)
      wait(50)
      verify(!underDialog.hovered, "the row under the dialog's box stays dark")
    }

    function test_a_recent_project_row_still_opens_once() {
      verify(!powerMenu.visible)
      var row = all(sv, function(i) { return isRow(i) && i.name === "proj1" })[0]
      verify(row, "the proj1 row")
      click(row)
      compare(top.log, ["openProject editor /home/u/Work/proj1"])
    }
  }
}

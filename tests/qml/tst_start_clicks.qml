import QtQuick
import QtTest
import "../../deck/plugin/fathom.deck"

// The Start menu with real mouse clicks: a click lands on what is on top and
// nothing under it (#13: Restart in the power menu also opened the Recent
// project beneath it). Run by tests/test_start_clicks.py.
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

    function powerRows() {
      return all(powerMenu, isRow)
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

    function test_a_recent_project_row_still_opens_once() {
      verify(!powerMenu.visible)
      var row = all(sv, function(i) { return isRow(i) && i.name === "proj1" })[0]
      verify(row, "the proj1 row")
      click(row)
      compare(top.log, ["openProject editor /home/u/Work/proj1"])
    }
  }
}

import QtQuick
import QtTest
import "fathom.clock"
import "fathom.clock/Model.js" as Model

// The clock dropdown's month (#14) with real clicks and the wheel: the
// arrows and the wheel step the month (up is back, as in Omarchy's), Today
// shows only for another month and goes back, the week column's heading
// changes the week start, and today is the one lit day. Run by
// tests/test_bar.py with the plugin staged as install.sh stages it.
Item {
  id: top
  width: 460
  height: 520
  property var log: []

  MonthGrid {
    id: grid
    x: 20; y: 20; width: 400
    // November 2026, Monday first, today the 20th (a Friday).
    weeks: Model.monthGrid(2026, 10, 1, "2026-11-20")
    weekdayLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    monthLabel: "November 2026"
    todayLabel: "Today"
    onStep: function(d) { top.log.push("step " + d) }
    onToday: top.log.push("today")
    onToggleWeekStart: top.log.push("weekStart")
  }

  function find(name) {
    function walk(item) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) { var f = walk(item.children[i]); if (f) return f }
      return null
    }
    return walk(grid)
  }
  function click(item) {
    var p = item.mapToItem(top, item.width / 2, item.height / 2)
    tc.mouseClick(top, p.x, p.y)
    tc.wait(30)
  }
  function lit(cell) {
    for (var i = 0; i < cell.children.length; i++)
      if (cell.children[i].radius !== undefined && cell.children[i].visible) return true
    return false
  }

  TestCase {
    id: tc
    name: "MonthGrid"
    when: windowShown

    function init() { top.log = []; grid.showToday = false; wait(30) }

    function test_six_weeks_from_the_monday_before() {
      compare(grid.weeks.length, 6)
      compare(grid.weeks[0].days[0].key, "2026-10-26", "the grid starts on the Monday before the 1st")
      compare(grid.weeks[0].week, 44, "ISO week of that row")
      verify(find("day 2026-11-01"), "the 1st is drawn")
      verify(find("day 2026-12-06"), "into December")
    }

    function test_today_is_the_one_lit_day() {
      verify(lit(find("day 2026-11-20")), "today lit")
      verify(!lit(find("day 2026-11-19")), "yesterday not")
    }

    function test_arrows_step_the_month() {
      click(find("previous"))
      click(find("next"))
      compare(top.log, ["step -1", "step 1"])
    }

    function test_today_shows_only_for_another_month() {
      verify(!find("today").visible)
      grid.showToday = true
      wait(30)
      verify(find("today").visible)
      click(find("today"))
      compare(top.log, ["today"])
    }

    function test_the_week_heading_changes_the_week_start() {
      click(find("weekHeading"))
      compare(top.log, ["weekStart"])
    }

    function test_the_wheel_steps_the_month() {
      var cell = find("day 2026-11-11")
      var p = cell.mapToItem(top, cell.width / 2, cell.height / 2)
      mouseWheel(top, p.x, p.y, 0, 120)
      mouseWheel(top, p.x, p.y, 0, -120)
      mouseWheel(top, p.x, p.y, 120, 0)
      compare(top.log, ["step -1", "step 1"], "up is back, down is on, sideways nothing")
    }
  }
}

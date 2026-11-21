import QtQuick
import "kit"

// The clock dropdown's month (#14), in Quick settings' look: the month and
// year between arrows (and Today, when another month shows), the weekdays
// with ISO week numbers down the left, and the days, today lit as Quick
// settings lights a tile. A read-out, as Omarchy's is: the days aren't
// buttons; the arrows, the wheel and the keys (Calendar.js) step the month.
// Clicking the week column's heading changes the first day of the week.
// Plain data in (Model.monthGrid's weeks), signals out.
Column {
  id: grid

  property var weeks: []
  property var weekdayLabels: []     // seven short names, in the week's order
  property string monthLabel: ""
  property string weekLabel: "W"
  property string weekTip: ""
  property bool showToday: false
  property string todayLabel: ""
  property string previousLabel: ""
  property string nextLabel: ""

  signal step(int delta)
  signal today()
  signal toggleWeekStart()

  readonly property real weekColumn: 30 * Skin.u
  readonly property real cell: (width - weekColumn) / 7
  readonly property real rowHeight: 36 * Skin.u

  spacing: 8 * Skin.u

  function g(cp) { return String.fromCodePoint(cp) }

  // The month, between its arrows.
  Item {
    width: parent.width
    height: 32 * Skin.u
    Pill {
      tabStop: false
      id: previous
      objectName: "previous"
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      glyph: grid.g(0xF0141)
      Accessible.name: grid.previousLabel
      onClicked: grid.step(-1)
    }
    Label {
      objectName: "month"
      anchors { left: previous.right; right: todayButton.visible ? todayButton.left : next.left; margins: 8 * Skin.u; verticalCenter: parent.verticalCenter }
      horizontalAlignment: Text.AlignHCenter
      text: grid.monthLabel
      font.pixelSize: 14 * Skin.u
      font.weight: Font.DemiBold
    }
    Pill {
      tabStop: false
      id: todayButton
      objectName: "today"
      visible: grid.showToday
      anchors { right: next.left; rightMargin: 6 * Skin.u; verticalCenter: parent.verticalCenter }
      text: grid.todayLabel
      onClicked: grid.today()
    }
    Pill {
      tabStop: false
      id: next
      objectName: "next"
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      glyph: grid.g(0xF0142)
      Accessible.name: grid.nextLabel
      onClicked: grid.step(1)
    }
  }

  Item {
    width: parent.width
    height: days.height

    Column {
      id: days
      width: parent.width

      // The weekdays.
      Row {
        height: 26 * Skin.u
        Rectangle {
          objectName: "weekHeading"
          width: grid.weekColumn
          height: parent.height
          radius: 8 * Skin.u
          color: weekMouse.containsMouse ? Skin.tint(Skin.fg, 0.11) : "transparent"
          Accessible.role: Accessible.Button
          Accessible.name: grid.weekTip
          Label {
            anchors.centerIn: parent
            text: grid.weekLabel
            color: Skin.accent
            font.pixelSize: 11 * Skin.u
          }
          MouseArea {
            id: weekMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: grid.toggleWeekStart()
          }
        }
        Repeater {
          model: grid.weekdayLabels
          delegate: Label {
            required property var modelData
            width: grid.cell
            height: 26 * Skin.u
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: String(modelData)
            color: Skin.dim
            font.pixelSize: 11 * Skin.u
          }
        }
      }

      // Six weeks.
      Repeater {
        model: grid.weeks.length
        delegate: Row {
          required property int index
          readonly property var week: grid.weeks[index] || ({ week: 0, days: [] })
          height: grid.rowHeight
          Label {
            width: grid.weekColumn
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: String(week.week)
            color: Skin.tint(Skin.fg, 0.4)
            font.pixelSize: 11 * Skin.u
          }
          Repeater {
            model: week.days.length
            delegate: Item {
              required property int index
              readonly property var day: week.days[index] || ({})
              objectName: "day " + day.key
              width: grid.cell
              height: grid.rowHeight
              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) - 4 * Skin.u
                height: width
                radius: width / 2
                visible: day.today === true
                color: Skin.tint(Skin.accent, 0.36)
                border.width: 1
                border.color: Skin.tint(Skin.accent, 0.8)
              }
              Label {
                anchors.centerIn: parent
                text: String(day.day || "")
                color: day.today ? Skin.fg
                  : !day.inMonth ? Skin.tint(Skin.fg, 0.3)
                  : day.weekend ? Skin.dim : Skin.fg
                font.pixelSize: 13 * Skin.u
                font.weight: day.today ? Font.Bold : Font.Normal
              }
            }
          }
        }
      }
    }

    // The wheel steps the month, one event a month, as in Omarchy's; a
    // sideways scroll (y 0) does nothing.
    MouseArea {
      anchors.fill: days
      acceptedButtons: Qt.NoButton
      onWheel: function(w) {
        if (w.angleDelta.y === 0) return
        grid.step(w.angleDelta.y > 0 ? -1 : 1)
      }
    }
  }
}

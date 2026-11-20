import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Model.js" as Model
import "Calendar.js" as C

// Fathom's clock on the bar (#14): Omarchy's clock label, with Fathom's own
// calendar under it (MonthGrid.qml and the kit). A clone of omarchy.clock
// (manifest.json): turning it on puts it where Omarchy's was, with its
// settings; turning it off puts Omarchy's back. It answers to omarchy.clock
// as Omarchy's does, so Super+Ctrl+Alt+D and `omarchy-shell omarchy.clock
// refresh|cycleFormat|toggleWeekStart` still work.
//
// The label is Omarchy's (its BarWidget.qml, MIT): the format from the
// entry's settings (format, formatAlt, verticalFormat, verticalFormatAlt),
// a click opens the calendar, a right-click walks the formats and keeps the
// new one, a middle-click opens Omarchy's time zone menu. The calendar keeps
// Omarchy's settings too: weekStartDay, birthYear, lifeExpectancy.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  // ---- The label (Omarchy's).
  property date displayDate: clock.date
  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")
  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))
  readonly property bool showsSeconds: Model.clockNeedsSeconds(configuredFormat)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property var formatLocale: Qt.locale(Commons.I18n.formatLocale)
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  function formatted(date) {
    var week = Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())
    week = week.split("").map(function(digit) { return Commons.I18n.formatNumber(digit) }).join("")
    return date.toLocaleString(root.formatLocale, configuredFormat.replace(/ww/g, week))
  }

  // ---- The calendar.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), formatLocale.firstDayOfWeek)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  property bool editingLife: false

  function refresh() {
    root.displayDate = new Date()
    root.today = new Date()
    goToToday()
  }
  function goToToday() {
    root.viewYear = root.today.getFullYear()
    root.viewMonth = root.today.getMonth()
  }
  function moveMonth(delta) {
    var next = Model.stepMonth(root.viewYear, root.viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  // As Omarchy's: applied here first, so it shows on the click, then written
  // to this item's entry in shell.json. The bar sets moduleName to the
  // entry's id (fathom.clock), so it's this clone's entry that changes.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function cycleFormat() {
    var next = Model.nextClockFormat(formatRing, String(configuredFormat))
    if (next === "" || next === configuredFormat) return
    var values = {}
    values[vertical ? "verticalFormat" : "format"] = next
    persistSettings(values)
  }
  function toggleWeekStart() {
    persistSettings({ weekStartDay: Model.weekStartSettingName(Model.toggledWeekStart(root.weekStart)) })
  }
  function saveLife(values) {
    var born = Model.parseBirthYear(values.born, root.today.getFullYear())
    var span = Model.parseLifeExpectancy(values.expectancy)
    if (born !== root.birthYear || span !== root.lifeExpectancy) persistSettings({ birthYear: born, lifeExpectancy: span })
    root.editingLife = false
  }

  // A popup from the middle of the bar shouldn't leave the bar's centre
  // indicators showing behind it (Omarchy's does the same).
  function suppressCentreReveal(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function") root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      if (panel.loadedContent) panel.loadedContent.rest()
      Qt.callLater(function() { if (root.opened) root.suppressCentreReveal(true) })
    } else {
      suppressCentreReveal(false)
      editingLife = false
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WallClock {
    id: clock
    step: root.showsSeconds ? 1000 : 60000
    onDateChanged: {
      root.displayDate = date
      // Midnight: today moves on, and so does the month shown if it was today's.
      if (Model.keyForDate(date) === root.todayKey) return
      var follow = root.viewingCurrentMonth
      root.today = date
      if (follow) root.goToToday()
    }
  }

  ShellIpc {
    target: "omarchy.clock"
    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // Every bar's copy, for `refresh` (BarWidget.broadcast's way).
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && typeof items[i][method] === "function") items[i][method]()
  }

  DropTheme { strings: catalog; screen: panel.screen }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: Commons.I18n.t("clock.toggleFormat")
    pressFeedbackButtons: Qt.NoButton

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.toggle()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent
      Repeater {
        model: root.verticalLines
        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    padding: 0
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.round(380 * DropSkin.u))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(680 * DropSkin.u))

    content: DropCard {
      title: root.today.toLocaleDateString(root.formatLocale, "dddd d MMMM")
      subtitle: catalog.t("clock.weekYear").arg(Model.isoWeek(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()))
                                           .arg(root.today.getFullYear())
      glyph: String.fromCodePoint(0xF00ED)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
      keyHandler: function(e) {
        if (root.editingLife) return false
        var act = C.keyAction(e.key, e.text)
        if (act === "month-1") root.moveMonth(-1)
        else if (act === "month+1") root.moveMonth(1)
        else if (act === "year-1") root.moveMonth(-12)
        else if (act === "year+1") root.moveMonth(12)
        else if (act === "today") root.goToToday()
        else if (act === "weekStart") root.toggleWeekStart()
        else return false
        return true
      }

      MonthGrid {
        width: parent.width
        weeks: root.weeks
        weekdayLabels: Model.weekdayOrder(root.weekStart).map(function(d) {
          return String(root.formatLocale.dayName(d, Locale.ShortFormat))
        })
        monthLabel: root.formatLocale.standaloneMonthName(root.viewMonth, Locale.LongFormat) + " " + root.viewYear
        weekLabel: catalog.t("clock.weekShort")
        weekTip: catalog.t("clock.startWeeksOn").arg(root.formatLocale.dayName(Model.toggledWeekStart(root.weekStart), Locale.LongFormat))
        showToday: !root.viewingCurrentMonth
        todayLabel: catalog.t("clock.today")
        previousLabel: catalog.t("clock.previousMonth")
        nextLabel: catalog.t("clock.nextMonth")
        onStep: function(d) { root.moveMonth(d) }
        onToday: root.goToToday()
        onToggleWeekStart: root.toggleWeekStart()
      }

      DropSections {
        width: parent.width
        model: C.sections({
          year: root.today.getFullYear(),
          yearDone: Model.yearProgress(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()),
          yearPercent: Model.yearProgressPercent(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()),
          birthYear: root.birthYear, age: root.age, lifeExpectancy: root.lifeExpectancy,
          lifeDone: Model.lifeProgress(root.age, root.lifeExpectancy),
          lifePercent: Model.lifeProgressPercent(root.age, root.lifeExpectancy),
          editing: root.editingLife
        }, function(k) { return catalog.t(k) })
        onPicked: function(key, value) {
          if (key === "year" && value === "doubleClick") root.editingLife = true
          else if (key === "life" && value === "doubleClick") root.persistSettings({ birthYear: 0 })
        }
        onSubmitted: function(key, values) { if (key === "lifeEdit") root.saveLife(values) }
        onCancelled: function(key) {
          root.editingLife = false
          if (panel.loadedContent) panel.loadedContent.rest()
        }
      }
    }
  }
}

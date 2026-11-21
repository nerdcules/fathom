import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Update.js" as U

// Fathom's system update on the bar (#14): Omarchy's update button, which
// shows only while an Omarchy update is waiting, with Fathom's dropdown
// under it: what the update is, Update now and Check again. A clone of
// omarchy.system-update (manifest.json): turning it on puts it where
// Omarchy's was; turning it off puts Omarchy's back. It answers to
// omarchy.system-update as Omarchy's does (`omarchy-shell
// omarchy.system-update refresh|clear`), and to open, close and toggle.
//
// As Omarchy's (its widgets/SystemUpdate.qml, MIT): omarchy-update-available
// every six hours (exit 0 when there's an update, its lines saying what),
// and omarchy-update in Omarchy's floating terminal. A right-click updates
// at once, as Omarchy's click did.
Panel {
  id: root
  moduleName: "omarchy.system-update"
  ipcTarget: "omarchy.system-update"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }

  property bool updateAvailable: false
  property string lines: ""

  function refresh() { if (!updateProc.running) updateProc.running = true }
  function clear() { updateAvailable = false; lines = "" }
  function runUpdate() {
    root.close()
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")
  }
  // Every bar's copy (BarWidget.broadcast's way).
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && typeof items[i][method] === "function") items[i][method]()
  }

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened && panel.loadedContent) panel.loadedContent.rest()

  ShellIpc {
    target: "omarchy.system-update"
    function refresh(): void { root.broadcast("refresh") }
    function clear(): void { root.broadcast("clear") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Process {
    id: updateProc
    command: ["omarchy-update-available"]
    stdout: StdioCollector { id: updateOut }
    onExited: function(exitCode) {
      root.updateAvailable = exitCode === 0
      root.lines = exitCode === 0 ? updateOut.text : ""
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    tooltipText: Commons.I18n.t("bar.pendingUpdates")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.runUpdate()
      else root.toggle()
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
    contentWidth: panel.fittedContentWidth(Math.round(380 * Skin.u))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(480 * Skin.u))

    content: DropCard {
      title: root.t("@bar.pendingUpdates")
      subtitle: root.updateAvailable ? root.t("su.ready") : root.t("su.none")
      glyph: ""
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: U.sections({ available: root.updateAvailable, checking: updateProc.running, lines: root.lines }, root.t)
        onPicked: function(key, value) {
          if (value === "update") root.runUpdate()
          else if (value === "check") root.refresh()
        }
      }
    }
  }
}

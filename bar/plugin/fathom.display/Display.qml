import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Display.js" as D

// Fathom's Display item on the bar (#14): Omarchy's Display button, with
// Fathom's own dropdown under it, drawn by the kit from Display.js
// sections(). It's a clone of omarchy.monitor (manifest.json,
// omarchy.clonedFrom): turning it on puts it where Omarchy's was, with its
// settings; turning it off puts Omarchy's back.
// It answers to omarchy.monitor as Omarchy's does, so Super+Ctrl+D and
// `omarchy-shell omarchy.monitor brightness|state` still work.
//
// The button: a click opens the dropdown; the wheel sets the brightness, 5%
// a notch, with Omarchy's on-screen display.
Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  property var info: D.parseState("")
  property int brightness: info.brightness
  property bool setQueued: false
  property int pendingBrightness: 0
  property real wheelRest: 0
  // While a text size change is on its way, the stop asked for; -1 follows
  // the shell's font size.
  property int textPending: -1

  readonly property var focused: D.focusedDisplay(info.displays, info.focused)
  readonly property var scales: focused ? D.availableScales(D.SCALES, focused.width, focused.height) : D.SCALES
  readonly property int scaleIndex: focused ? D.matchingScaleIndex(scales, info.scale, focused.width, focused.height) : -1
  readonly property int textIndex: textPending >= 0 ? textPending : D.nearestStop(Style.font.baseSize)

  ShellIpc {
    target: "omarchy.monitor"
    function brightness(percent: string): string { root.setBrightness(Number(percent)); return "got " + root.pendingBrightness }
    function state(): string {
      return JSON.stringify({ brightness: root.brightness, brightnessAvailable: root.brightness >= 0,
                              focusedMonitor: root.info.focused, scale: root.info.scale, displays: root.info.displays })
    }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() { if (!stateProc.running) stateProc.running = true }

  // As Omarchy's: the newest value wins, one write at a time.
  function setBrightness(value) {
    if (root.brightness < 0) return
    var percent = D.clampBrightness(value)
    root.brightness = percent
    root.pendingBrightness = percent
    if (setProc.running) { root.setQueued = true; return }
    root.setQueued = false
    setProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.info.focused, percent + "%"]
    setProc.running = true
  }

  function setScale(scale) {
    if (D.SCALES.indexOf(String(scale)) === -1) return
    actionProc.command = ["omarchy-hyprland-monitor-scaling", String(scale)]
    if (!actionProc.running) actionProc.running = true
  }

  function setTextIndex(i) {
    i = Math.max(0, Math.min(D.TEXT_STOPS.length - 1, i))
    root.textPending = i
    textProc.command = ["omarchy-display-text-size", String(D.TEXT_STOPS[i])]
    if (!textProc.running) textProc.running = true
  }

  // Through Hyprland's Lua API, as Omarchy's does (`hyprctl keyword` is
  // refused under the Lua config). The name comes from Hyprland's own list
  // and is quoted for Lua; the last display that's on stays on.
  function toggleDisplay(name) {
    var rows = D.displayRows(root.info.displays)
    var row = null
    for (var i = 0; i < rows.length; i++) if (rows[i].name === name) row = rows[i]
    if (!row || !row.canToggle) return
    var output = '"' + name.replace(/[\\"]/g, "\\$&") + '"'
    actionProc.command = ["hyprctl", "eval", "hl.monitor({ output = " + output + ", disabled = " + (row.enabled ? "true" : "false") + " })"]
    if (!actionProc.running) actionProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) {
    refresh()
    if (panel.loadedContent) panel.loadedContent.rest()
  }

  // Brightness changed elsewhere shows while the dropdown is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.info = D.parseState(text)
        // Not while a write is on its way: the value just set stands.
        if (!setProc.running) root.brightness = root.info.brightness
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running && root.setQueued) root.setBrightness(root.pendingBrightness)
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  Process {
    id: textProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // The shell's font size catching up ends the wait.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      if (root.textPending >= 0 && D.nearestStop(Style.font.baseSize) === root.textPending) root.textPending = -1
    }
  }

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "\u{F037A}" : "\u{F0379}"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (root.brightness < 0) return
      var wheel = Util.wheelSteps(root.wheelRest, delta)
      root.wheelRest = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightness + wheel.steps * 5)
      if (root.bar && root.bar.shell)
        root.bar.shell.summon("omarchy.osd", JSON.stringify({ icon: "brightness", value: root.brightness }))
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    padding: 0
    focusTarget: panel.loadedContent
    // Fathom's sizes, as Quick settings has them (Skin.u), not Omarchy's.
    contentWidth: panel.fittedContentWidth(Math.round(380 * Skin.u))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(640 * Skin.u))

    content: DropCard {
      title: catalog.t("display.title")
      subtitle: root.focused ? [root.focused.name, root.focused.width + "×" + root.focused.height].join(" · ") : ""
      glyph: D.g(root.info.displays.length > 1 ? 0xF037A : 0xF0379)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: D.sections({ brightness: root.brightness, textIndex: root.textIndex, scales: root.scales,
                            scaleIndex: root.scaleIndex, displays: D.displayRows(root.info.displays),
                            width: root.focused ? root.focused.width : 0, height: root.focused ? root.focused.height : 0 },
                          function(k) { return catalog.t(k) })
        onMoved: function(key, v) {
          if (key === "brightness") root.setBrightness(Math.round(v * 100))
          else if (key === "textSize") root.setTextIndex(Math.round(v * (D.TEXT_STOPS.length - 1)))
        }
        onPicked: function(key, value) {
          if (key === "scale") root.setScale(value)
          else if (key === "displays") root.toggleDisplay(value)
        }
      }
    }
  }
}

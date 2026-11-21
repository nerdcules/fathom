import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "KeyboardLayoutModel.js" as KeyboardLayoutModel
import "Layouts.js" as L

// Fathom's keyboard layout on the bar (#14): Omarchy's layout label, with
// Fathom's dropdown under it: every layout, the one in use lit, to pick one;
// and the input method, when there's more than one. A clone of
// omarchy.keyboard-layout (manifest.json): turning it on puts it where
// Omarchy's was; turning it off puts Omarchy's back. As Omarchy's, it shows
// only with two layouts or two input methods.
//
// The keyboards are read as Omarchy's widget reads them (its widgets/
// KeyboardLayout.qml and KeyboardLayoutModel.js, MIT; the model copied
// unchanged): `hyprctl -j devices` on Hyprland's layout events, on a device
// change and until a reading settles; the keyboard being typed on chosen by
// Omarchy's rules; and a switch moving every keyboard holding the same layout
// list, by index, so they stay together. A right-click goes to the next
// layout (or input method), as Omarchy's click did.
Panel {
  id: root
  moduleName: "omarchy.keyboard-layout"
  ipcTarget: "omarchy.keyboard-layout"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }

  property string layoutFull: ""
  property string keyboardName: ""
  property string typedKeyboardName: ""
  property bool keyboardUnresolved: false
  property bool multipleLayouts: true
  property int layoutIndex: 0
  property int layoutCount: 0
  property var syncNames: []
  property var keyboard: null
  property var layoutBriefs: ({})
  property var layoutNames: ({})
  property bool layoutsRead: false
  property bool briefsRequested: false
  readonly property bool needsBriefs: layoutsRead && (multipleLayouts || multipleInputs)
  onNeedsBriefsChanged: loadBriefs()
  function loadBriefs() {
    if (!needsBriefs || briefsRequested) return
    briefsRequested = true
    briefsProc.running = true
  }
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)
  readonly property var inputState: InputMethodState.state
  readonly property bool multipleInputs: (inputState.methods || []).length > 1
  readonly property string inputLabel: KeyboardLayoutModel.inputLabel(inputState, layoutLabel)

  property bool refreshPending: false
  function refresh() {
    if (queryProc.running) { refreshPending = true; return }
    refreshPending = false
    queryProc.running = true
  }
  function typedKeyboards(keyboards) { return keyboards.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name)) }
  function selectKeyboard(typed) { return KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName) }

  // Every keyboard holding the same list goes to one index (Omarchy's rule).
  function switchTo(index) {
    if (!root.bar || root.layoutCount < 2 || root.syncNames.length === 0) return
    var next = ((index % root.layoutCount) + root.layoutCount) % root.layoutCount
    root.bar.run(root.syncNames.map(name => "hyprctl switchxkblayout " + Util.shellQuote(name) + " " + next).join("; "))
    refreshTimer.restart()
  }
  function cycle() {
    if (root.multipleInputs) InputMethodState.cycle()
    else if (root.multipleLayouts) root.switchTo(root.layoutIndex + 1)
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { refresh(); if (panel.loadedContent) panel.loadedContent.rest() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) { stallTimer.restart(); return }
      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let listed
        try { listed = JSON.parse(text || "{}").keyboards } catch (e) { root.keyboardUnresolved = true; return }
        if (!Array.isArray(listed)) { root.keyboardUnresolved = true; return }
        const typed = root.typedKeyboards(listed)
        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          root.keyboardUnresolved = true
          if (typed.length === 0) { root.layoutFull = ""; root.keyboardName = ""; root.keyboard = null }
          return
        }
        root.keyboardUnresolved = false
        root.keyboard = kb
        root.keyboardName = String(kb.name || "")
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutsRead = true
        root.layoutIndex = kb.active_layout_index || 0
        root.layoutCount = kb.layout === undefined ? 0 : String(kb.layout).split(",").length
        root.syncNames = listed.filter(k => String(k.layout) === String(kb.layout)).map(k => String(k.name || "")).filter(n => n !== "")
        root.layoutFull = kb.active_keymap
      }
    }
  }
  // xkb's table: a short code for the label (Omarchy's), and each layout's
  // name for the list.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
        root.layoutNames = L.layoutNames(text)
      }
    }
  }
  Timer { id: refreshTimer; interval: 600; onTriggered: root.refresh() }
  Timer { id: stallTimer; interval: 5000; onTriggered: { queryProc.running = false; refreshTimer.restart() } }
  Connections { target: InputDevices; function onChanged() { root.refresh() } }
  Timer {
    interval: 10000
    running: !root.keyboardName || root.keyboardUnresolved || !InputDevices.healthy
    repeat: true
    onTriggered: root.refresh()
  }

  ShellIpc {
    target: "omarchy.keyboard-layout"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function next(): void { root.cycle() }
  }

  visible: inputLabel !== "" && KeyboardLayoutModel.showIndicator(layoutLabel, multipleLayouts, multipleInputs)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  DropTheme { strings: catalog; screen: panel.screen }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.inputLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: KeyboardLayoutModel.inputTooltip(root.inputState, root.layoutFull, root.multipleLayouts)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycle()
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
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(560 * Skin.u))

    content: DropCard {
      title: root.t("kb.title")
      subtitle: root.layoutFull
      glyph: String.fromCodePoint(0xF030C)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: L.sections({
          layouts: L.layouts(root.keyboard, root.layoutNames), index: root.layoutIndex,
          methods: (root.inputState.methods || []).length,
          method: root.inputState.name ? String(root.inputState.name).replace(/^Keyboard - /, "") : ""
        }, root.t)
        onPicked: function(key, value) {
          if (key === "layout") root.switchTo(Number(value))
          else if (key === "input") InputMethodState.cycle()
        }
      }
    }
  }
}

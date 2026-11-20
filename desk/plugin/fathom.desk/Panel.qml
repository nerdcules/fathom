import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."
import "Desk.js" as D

// Fathom's desk: Alt+Tab, Task view, Snap layouts and Quick settings, in one
// overlay the shell keeps loaded so Alt+Tab opens at once.
//
//   shell summon fathom.desk '{"view":"tasks"}'   (or "snap", "quick"):
//       open that view, or close it if it's the one showing
//   shell call fathom.desk step 1 | step -1 | commit | cancel
//       Alt+Tab, from Hyprland (see desk/hypr/fathom-desk.lua)
//   shell call fathom.desk tasks 1 | tasks -1 | tasksRelease | tasksCancel
//       Super+Tab: open Task view, then look at the next or previous
//       workspace; letting go of Super goes there
//
// It reads windows through `fathom-desk state` when a view opens, and keeps
// that list current from Hyprland's events while one shows. Nothing is read
// while nothing shows, beyond keeping the list from the last time.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property string view: ""                 // "", "switch", "tasks", "snap", "quick"
  readonly property bool opened: view !== ""
  property var state: null                 // the last `fathom-desk state`
  property var settings: null              // the last `fathom-desk settings`

  // Alt+Tab.
  property int selected: -1
  property bool committed: false
  property bool reveal: false              // shown after a moment, so a quick tap doesn't flash

  readonly property string home: Quickshell.env("HOME")
  readonly property string deskTool: home + "/.local/bin/fathom-desk"
  readonly property string pluginId: (manifest && manifest.id) || "fathom.desk"

  readonly property var windows: D.windowList(state ? state.clients : [])
  readonly property var monitor: {
    var list = state && Array.isArray(state.monitors) ? state.monitors : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].focused) return list[i]
    return list.length > 0 ? list[0] : null
  }
  readonly property int currentWorkspace: monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) || 0 : 0
  readonly property var workspaces: D.workspaceList(state ? state.workspaces : [], currentWorkspace)
  readonly property string activeAddress: state && state.active && D.validAddress(state.active.address) ? state.active.address : ""

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  Binding { target: Skin; property: "fg"; value: Commons.Color.foreground }
  Binding { target: Skin; property: "bg"; value: Commons.Color.background }
  Binding { target: Skin; property: "accent"; value: Commons.Color.accent }
  Binding { target: Skin; property: "urgent"; value: Commons.Color.urgent }
  Binding { target: Skin; property: "fontFamily"; value: Style.font.family }
  Binding { target: Skin; property: "motion"; value: Style.duration(100) / 100 }
  Binding { target: Skin; property: "strings"; value: catalog }
  Binding { target: Skin; property: "radius"; value: Style.cornerRadius }
  Binding { target: Skin; property: "glassAlpha"; value: Commons.Color.menu.background.a }
  Binding { target: Skin; property: "edgeAlpha"; value: Commons.Color.menu.border.a }

  // The glow is Fathom's own, so it lives only in look.json (fathom-look);
  // the rest of the look reaches here through the theme.
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/fathom/look.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var look = JSON.parse(text())
        Skin.glow = look.glow !== false
      } catch (e) { Skin.glow = true }
    }
    onLoadFailed: Skin.glow = true
  }

  // ------------------------------------------------ opening and closing

  function open(payloadJson) {
    var wanted = ""
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && ["tasks", "snap", "quick"].indexOf(payload.view) !== -1) wanted = payload.view
    } catch (e) {}
    if (wanted === "") return
    if (view === wanted) { dismiss(); return }
    if (view === "switch") cancel("")
    show(wanted)
  }

  function show(which) {
    view = which
    committed = false
    reveal = which !== "switch"
    if (!blurProc.running) blurProc.running = true
    read()
    if (which === "quick") readSettings()
  }

  // The shell's `hide`.
  function close() {
    view = ""
    tasksStepped = false
    reveal = false
    revealTimer.stop()
  }

  // Esc, a click outside, or done: tell the shell, which calls close().
  function dismiss() {
    if (shell && typeof shell.hide === "function" && view !== "switch") shell.hide(pluginId)
    close()
  }

  function read() {
    if (!stateProc.running) stateProc.running = true
    else stateAgain = true
  }
  property bool stateAgain: false

  function readSettings() {
    if (!settingsProc.running) settingsProc.running = true
  }

  // Run Hyprland commands built by Desk.js (null ones are skipped: they
  // failed a check).
  function dispatch(commands) {
    for (var i = 0; i < commands.length; i++) if (commands[i]) Hyprland.dispatch(commands[i])
  }

  function activate(win) {
    dispatch(D.activate(win, currentWorkspace))
  }

  function toplevelFor(address) {
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var bare = String(address || "").replace(/^0x/, "")
    for (var i = 0; i < list.length; i++) {
      var a = String(list[i].address || "").replace(/^0x/, "")
      if (a === bare) return list[i].wayland || null
    }
    return null
  }

  // ------------------------------------------------ Alt+Tab

  // From Hyprland: "1" forward, "-1" back. The first opens the switcher.
  function step(arg) {
    var delta = Number(arg) < 0 ? -1 : 1
    if (view !== "switch") {
      if (view !== "") close()
      view = "switch"
      committed = false
      reveal = false
      selected = D.stepIndex(0, windows.length, delta, true)
      if (!blurProc.running) blurProc.running = true
      revealTimer.restart()
      read()
      return "ok"
    }
    selected = D.stepIndex(selected, windows.length, delta, false)
    reveal = true
    return "ok"
  }

  // Alt let go: bring the chosen window forward.
  function commit(arg) {
    if (view !== "switch" || committed) return "ok"
    committed = true
    var win = selected >= 0 && selected < windows.length ? windows[selected] : null
    close()
    if (win) activate(win)
    return "ok"
  }

  function cancel(arg) {
    if (view !== "switch") return "ok"
    committed = true
    close()
    // Hyprland's side stops watching Alt.
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
    return "ok"
  }

  // ------------------------------------------------ Super+Tab

  // From Hyprland: Super+Tab opens Task view; Tab again, Super still held,
  // looks at the next workspace ("1") or the one before ("-1"). Letting go
  // of Super goes to the workspace looked at, if Tab moved it; after a plain
  // tap Task view stays open for the mouse or the keys.
  property bool tasksStepped: false

  function tasks(arg) {
    var delta = Number(arg) < 0 ? -1 : 1
    if (view !== "tasks") {
      tasksStepped = false
      var payload = JSON.stringify({ view: "tasks" })
      if (shell && typeof shell.summon === "function") shell.summon(pluginId, payload)
      else open(payload)
      return "ok"
    }
    if (taskLoader.item) {
      taskLoader.item.lookAt(delta)
      tasksStepped = true
    }
    return "ok"
  }

  // Super let go.
  function tasksRelease(arg) {
    if (view !== "tasks" || !tasksStepped) return "ok"
    tasksStepped = false
    if (taskLoader.item) taskLoader.item.goTo(taskLoader.item.shownWorkspace)
    return "ok"
  }

  function tasksCancel(arg) {
    tasksStepped = false
    if (view === "tasks") dismiss()
    return "ok"
  }

  Timer {
    id: revealTimer
    interval: 120
    onTriggered: if (root.view === "switch") root.reveal = true
  }

  // ------------------------------------------------ reading

  Process {
    id: blurProc
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var o = JSON.parse(text)
          Skin.glass = o.bool !== undefined ? !!o.bool : !!o.int
        } catch (e) {}
      }
    }
  }

  Process {
    id: stateProc
    command: [root.deskTool, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) {}
        if (!parsed || !Array.isArray(parsed.clients)) return
        var before = root.selected >= 0 && root.selected < root.windows.length ? root.windows[root.selected].address : ""
        root.state = parsed
        // The switcher keeps its choice by window, not by place in the list.
        if (root.view === "switch") {
          var found = -1
          for (var i = 0; i < root.windows.length; i++) if (root.windows[i].address === before) found = i
          if (found !== -1) root.selected = found
          else if (root.selected >= root.windows.length) root.selected = root.windows.length - 1
          else if (root.selected < 0 && root.windows.length > 0) root.selected = Math.min(1, root.windows.length - 1)
        }
      }
    }
    onExited: if (root.stateAgain) { root.stateAgain = false; running = true }
  }

  Process {
    id: settingsProc
    command: [root.deskTool, "settings"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object") root.settings = parsed
        } catch (e) {}
      }
    }
  }

  // While a view shows, windows opening, closing and moving update it.
  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      var n = event && event.name ? String(event.name) : ""
      if (/^(openwindow|closewindow|movewindow|movewindowv2|workspace|workspacev2|createworkspace|destroyworkspace|activewindowv2|changefloatingmode|windowtitlev2)$/.test(n))
        settle.restart()
    }
  }
  Timer { id: settle; interval: 60; onTriggered: root.read() }

  // Run a `fathom-desk set` and read the settings again after.
  function setSetting(what, value) {
    var proc = setComponent.createObject(root, { command: [deskTool, "set", what, String(value)] })
    proc.running = true
  }
  Component {
    id: setComponent
    Process {
      onExited: { root.readSettings(); destroy() }
    }
  }

  // Quick settings reads again every few seconds while it shows.
  Timer {
    interval: 4000
    repeat: true
    running: root.view === "quick"
    onTriggered: root.readSettings()
  }

  // ------------------------------------------------ the overlay

  OverlayWindow {
    id: window
    shown: root.opened && root.reveal
    WlrLayershell.namespace: "fathom-desk"

    Item {
      id: stage
      anchors.fill: parent
      readonly property real scaleFactor: Math.max(0.7, Math.min(1.25, Math.min(width / 1600, height / 1000)))
      Binding { target: Skin; property: "u"; value: stage.scaleFactor }

      focus: true
      Keys.onPressed: function(e) {
        if (root.view === "switch") switchView.key(e)
        else if (root.view === "tasks" && taskLoader.item) taskLoader.item.key(e)
        else if (root.view === "snap" && snapLoader.item) snapLoader.item.key(e)
        else if (root.view === "quick" && quickLoader.item) quickLoader.item.key(e)
      }
      Keys.onReleased: function(e) {
        // Alt let go while the switcher has the keyboard.
        if (root.view === "switch" && (e.key === Qt.Key_Alt || e.key === Qt.Key_AltGr || e.key === Qt.Key_Meta)) {
          e.accepted = true
          Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
          root.commit("")
        }
        // Super let go while Task view has the keyboard, after Tab moved it.
        else if (root.view === "tasks" && (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta)) {
          e.accepted = true
          if (root.tasksStepped) {
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
            root.tasksRelease("")
          }
        }
      }

      SwitchView {
        id: switchView
        anchors.fill: parent
        visible: root.view === "switch"
        windows: root.windows
        selected: root.selected
        host: root
        onPicked: function(i) { root.selected = i; root.commit(""); Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"]) }
        onMoveRequested: function(delta) { root.selected = D.stepIndex(root.selected, root.windows.length, delta, false) }
        onCancelRequested: root.cancel("")
      }

      // The other views are made when they open, and let go when they close.
      Loader {
        id: taskLoader
        anchors.fill: parent
        active: root.view === "tasks"
        sourceComponent: TaskView {
          shown: window.contentRevealed
          host: root
          onDone: root.dismiss()
        }
      }

      Loader {
        id: snapLoader
        anchors.fill: parent
        active: root.view === "snap"
        sourceComponent: SnapView {
          shown: window.contentRevealed
          host: root
          onDone: root.dismiss()
        }
      }

      Loader {
        id: quickLoader
        anchors.fill: parent
        active: root.view === "quick"
        sourceComponent: QuickView {
          shown: window.contentRevealed
          host: root
          onDone: root.dismiss()
        }
      }
    }

    onContentRevealedChanged: if (contentRevealed) stage.forceActiveFocus()
  }
}

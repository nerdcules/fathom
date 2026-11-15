import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."

// Fathom's Command Deck, with its two pages: Deck and Care. The shell loads
// this only while it's open, so it reads the machine (through `fathom-deck
// status` and `fathom-care status`) only then: every few seconds while it's
// on screen, never in the background. Care's hourly check runs from a
// systemd timer instead.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string page: "deck"
  property var info: null
  property var care: null
  property string error: ""
  property var busy: ({})
  property var cleaning: ({})

  readonly property string home: Quickshell.env("HOME")
  readonly property string deckTool: home + "/.local/bin/fathom-deck"
  readonly property string careTool: home + "/.local/bin/fathom-care"
  readonly property string pluginId: (manifest && manifest.id) || "fathom.deck"
  // Care runs its own check when it's this stale (the timer may be off).
  readonly property int staleSeconds: 3 * 3600

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  // The look every part reads.
  Binding { target: Skin; property: "fg"; value: Commons.Color.foreground }
  Binding { target: Skin; property: "bg"; value: Commons.Color.background }
  Binding { target: Skin; property: "accent"; value: Commons.Color.accent }
  Binding { target: Skin; property: "urgent"; value: Commons.Color.urgent }
  Binding { target: Skin; property: "fontFamily"; value: Style.font.family }
  Binding { target: Skin; property: "motion"; value: Style.duration(100) / 100 }
  Binding { target: Skin; property: "locale"; value: Qt.locale(Commons.I18n.formatLocale) }
  Binding { target: Skin; property: "strings"; value: catalog }
  Component.onCompleted: Skin.fmt = function(v, d) { return Commons.I18n.formatNumber(v, d) }

  // `shell summon fathom.deck '{"page":"care"}'`. Asking for the page that
  // is already showing closes the deck, so one key opens and closes it.
  function open(payloadJson) {
    var wanted = "deck"
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && payload.page === "care") wanted = "care"
    } catch (e) {}
    if (opened && page === wanted) {
      dismiss()
      return
    }
    page = wanted
    opened = true
    refresh()
  }

  // Host-initiated close (`shell hide`). Esc and the scrim go through
  // dismiss() so the shell's idea of what is open stays right.
  function close() {
    opened = false
    pause.stop()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function refresh() {
    if (!opened) return
    if (page === "deck") {
      if (!deckProc.running) deckProc.running = true
    } else if (!careProc.running) {
      careProc.running = true
    }
  }

  function setPage(p) {
    page = p
    pause.stop()
    refresh()
  }

  function without(map, keys) {
    var next = ({})
    for (var k in map) if (keys.indexOf(k) === -1) next[k] = map[k]
    return next
  }

  function withKeys(map, keys) {
    var next = without(map, keys)
    for (var i = 0; i < keys.length; i++) next[keys[i]] = true
    return next
  }

  function parse(text) {
    try {
      var parsed = JSON.parse(text)
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.error = catalog.t("readFailed").arg(String(e).slice(0, 120))
      return null
    }
  }

  // Run a command and refresh when it ends; `then` runs first.
  function run(command, then) {
    var proc = actionComponent.createObject(root, { command: command, then: then || null })
    proc.running = true
  }

  // Run something that may ask for a password or opens its own window:
  // close the deck so nothing sits on top of it.
  function handOff(command) {
    Quickshell.execDetached(command)
    dismiss()
  }

  function containerAction(action, name) {
    if (busy[name] === true) return
    busy = withKeys(busy, [name])
    run([deckTool, "container", action, name], function() { root.busy = root.without(root.busy, [name]) })
  }

  function clean(ids, needsRoot) {
    if (ids.length === 0) return
    if (needsRoot) {
      handOff([careTool, "clean", "--notify"].concat(ids))
      return
    }
    cleaning = withKeys(cleaning, ids)
    run([careTool, "clean"].concat(ids), function() { root.cleaning = root.without(root.cleaning, ids) })
  }

  function restartUnit(scope, unit) {
    if (scope === "user") run([careTool, "restart", "user", unit])
    else handOff([careTool, "restart", "system", unit])
  }

  function check() {
    if (!checkProc.running) checkProc.running = true
  }

  Process {
    id: deckProc
    command: [root.deckTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (parsed && parsed.system) { root.info = parsed; root.error = "" }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("fathom.deck:", msg.slice(0, 400))
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  Process {
    id: careProc
    command: [root.careTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (!parsed || !parsed.disk) return
        root.care = parsed
        root.error = ""
        var stale = !parsed.checkedAt || parsed.time - parsed.checkedAt > root.staleSeconds
        if (stale && parsed.checking !== true) root.check()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("fathom.deck (care):", msg.slice(0, 400))
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  Process {
    id: checkProc
    command: [root.careTool, "check"]
    onExited: root.refresh()
  }

  // The next reading starts a little after the last one finished.
  Timer {
    id: pause
    interval: root.page === "deck" ? 2500 : 5000
    onTriggered: root.refresh()
  }

  Component {
    id: actionComponent
    Process {
      property var then: null
      onExited: function(exitCode) {
        if (typeof then === "function") then()
        root.refresh()
        destroy()
      }
    }
  }

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "fathom-deck"

    DeckView {
      id: view
      anchors.fill: parent
      shown: window.contentRevealed
      page: root.page
      info: root.info
      care: root.care
      error: root.error
      busy: root.busy
      cleaning: root.cleaning
      checking: checkProc.running

      onCloseRequested: root.dismiss()
      onPageRequested: function(p) { root.setPage(p) }
      onContainerAction: function(action, name) { root.containerAction(action, name) }
      onLogsRequested: function(name) { root.handOff([root.deckTool, "logs", name]) }
      onDockerRequested: root.handOff([root.deckTool, "docker"])
      onCleanRequested: function(ids, needsRoot) { root.clean(ids, needsRoot) }
      onRestartRequested: function(scope, unit) { root.restartUnit(scope, unit) }
      onUnitLogRequested: function(scope, unit) { root.handOff([root.careTool, "log", scope, unit]) }
      onUpdateRequested: root.handOff([root.careTool, "update"])
      onCheckRequested: root.check()
    }

    onContentRevealedChanged: if (contentRevealed) view.forceActiveFocus()
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Fathom's Command Deck. The shell loads this only while the deck is open,
// so it reads the machine (through `fathom-deck status`) only then: every
// few seconds while it's on screen, never in the background.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var info: null
  property string error: ""
  property var busy: ({})

  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/fathom-deck"
  readonly property string pluginId: (manifest && manifest.id) || "fathom.deck"

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
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
    if (!opened || statusProc.running) return
    statusProc.running = true
  }

  function setBusy(name, on) {
    var next = ({})
    for (var k in busy) if (k !== name) next[k] = busy[k]
    if (on) next[name] = true
    busy = next
  }

  function runAction(action, name) {
    if (busy[name] === true) return
    setBusy(name, true)
    var proc = actionComponent.createObject(root, { name: name, command: [root.tool, "container", action, name] })
    proc.running = true
  }

  Process {
    id: statusProc
    command: [root.tool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object" && parsed.system) {
            root.info = parsed
            root.error = ""
          }
        } catch (e) {
          root.error = catalog.t("readFailed").arg(String(e).slice(0, 120))
        }
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

  // The next reading starts a little after the last one finished.
  Timer {
    id: pause
    interval: 2500
    onTriggered: root.refresh()
  }

  Component {
    id: actionComponent
    Process {
      property string name: ""
      onExited: function(exitCode) {
        root.setBusy(name, false)
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
      info: root.info
      error: root.error
      busy: root.busy
      fg: Commons.Color.foreground
      bg: Commons.Color.background
      accent: Commons.Color.accent
      urgent: Commons.Color.urgent
      fontFamily: Style.font.family
      motion: Style.duration(100) / 100
      locale: Qt.locale(Commons.I18n.formatLocale)
      strings: catalog
      fmt: function(v, d) { return Commons.I18n.formatNumber(v, d) }

      onCloseRequested: root.dismiss()
      onContainerAction: function(action, name) { root.runAction(action, name) }
      onLogsRequested: function(name) { Quickshell.execDetached([root.tool, "logs", name]); root.dismiss() }
      onDockerRequested: { Quickshell.execDetached([root.tool, "docker"]); root.dismiss() }
    }

    onContentRevealedChanged: if (contentRevealed) view.forceActiveFocus()
  }
}

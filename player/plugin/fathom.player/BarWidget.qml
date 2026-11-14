import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Sanitize.js" as Sanitize

// What the Fathom mini-player is playing, in the bar. Shown only while the
// player runs. Click to pause or resume, scroll to skip, right-click to close.
//
// It listens on mpv's IPC socket and asks mpv to report changes, so it costs
// nothing while idle beyond a connection attempt every few seconds.
//
// Settings (shell.json layout entry): maxChars (title length in the bar,
// default 28), skip (seconds per scroll step, default 5).
BarWidget {
  id: root
  moduleName: "fathom.player"

  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fathom-player.sock"
  readonly property int maxChars: Math.max(8, Number(setting("maxChars", 28)) || 28)
  readonly property int skip: Math.max(1, Number(setting("skip", 5)) || 5)

  property string title: ""
  property bool paused: false
  property bool muted: false
  property real position: 0
  property real duration: 0

  readonly property bool live: mpv.connected
  readonly property string glyph: paused ? "" : ""
  readonly property string shownTitle: title !== "" ? Sanitize.ellipsize(title, maxChars) : strings.t("loading")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  visible: live
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function send(args) {
    if (!mpv.connected) return
    mpv.write(JSON.stringify({ command: args }) + "\n")
    mpv.flush()
  }

  function handle(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || typeof msg !== "object") return
    if (msg.event === "property-change") {
      if (msg.name === "media-title") root.title = Sanitize.plain(msg.data, 300)
      else if (msg.name === "pause") root.paused = msg.data === true
      else if (msg.name === "mute") root.muted = msg.data === true
      else if (msg.name === "duration") root.duration = Math.max(0, Number(msg.data) || 0)
    } else if (msg.request_id === 7 && msg.error === "success") {
      root.position = Math.max(0, Number(msg.data) || 0)
    }
  }

  function reset() {
    title = ""
    paused = false
    muted = false
    position = 0
    duration = 0
  }

  Socket {
    id: mpv
    path: root.socketPath
    parser: SplitParser { onRead: function(data) { root.handle(data) } }
    onConnectionStateChanged: {
      if (connected) {
        root.send(["observe_property", 1, "media-title"])
        root.send(["observe_property", 2, "pause"])
        root.send(["observe_property", 3, "mute"])
        root.send(["observe_property", 4, "duration"])
      } else {
        root.reset()
      }
    }
  }

  // Look for the player while it isn't running.
  Timer {
    interval: 2500
    running: !mpv.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: mpv.connected = true
  }

  // The playback position changes constantly, so ask for it once a second
  // rather than having mpv report every frame.
  Timer {
    interval: 1000
    running: mpv.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      mpv.write(JSON.stringify({ command: ["get_property", "time-pos"], request_id: 7 }) + "\n")
      mpv.flush()
    }
  }

  readonly property string tooltip: [
    title !== "" ? title : strings.t("loading"),
    strings.t("position").arg(Sanitize.clock(position)).arg(duration > 0 ? Sanitize.clock(duration) : "--:--")
      + (paused ? "  ·  " + strings.t("paused") : "")
      + (muted ? "  ·  " + strings.t("muted") : ""),
    strings.t("hint")
  ].join("\n")

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.glyph : root.glyph + "  " + root.shownTitle
    hasVisualContent: true
    horizontalMargin: 8.75
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.send(["quit"])
      else if (b === Qt.MiddleButton) root.send(["cycle", "mute"])
      else root.send(["cycle", "pause"])
    }

    onWheelMoved: function(delta) {
      root.send(["seek", delta > 0 ? root.skip : -root.skip, "relative"])
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Mic.js" as M

// Fathom's microphone on the bar (#14): Omarchy's microphone icon, with
// Fathom's dropdown under it: on or muted, the input level, the inputs to
// choose from, and the apps using it. A clone of omarchy.microphone
// (manifest.json): turning it on puts it where Omarchy's was; turning it off
// puts Omarchy's back.
//
// As Omarchy's (its widgets/Microphone.qml, MIT): the default PipeWire
// source, a virtual one's volume and mute through wpctl (UntypedInput), and
// "in use" as any app's recording stream that isn't the shell's own meters
// or a platform's always-on processing. A right-click mutes, the wheel turns
// it up or down, a middle-click opens Omarchy's audio panel, as Omarchy's.
Panel {
  id: root
  moduleName: "omarchy.microphone"
  ipcTarget: "omarchy.microphone"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }

  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool viaWpctl: UntypedInput.active
  readonly property bool muted: viaWpctl ? (!UntypedInput.known || UntypedInput.muted) : (source && source.audio ? source.audio.muted : true)
  readonly property real volume: viaWpctl ? UntypedInput.volume : (source && source.audio ? source.audio.volume : 0)
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var nodeNames: {
    var names = []
    for (var i = 0; i < nodes.length; i++) if (nodes[i] && nodes[i].name) names.push(String(nodes[i].name))
    return names
  }
  readonly property var activeStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (!node || !node.isStream || node.isSink !== false || node.audio?.muted) continue
      if (AudioNodes.isShellLevelMeter(node.name) || AudioNodes.platformHides(node.name, nodeNames)) continue
      list.push(node)
    }
    return list
  }
  readonly property bool inUse: activeStreams.length > 0 && !muted
  // The microphones to choose from: every source that isn't a stream or a
  // monitor of an output.
  readonly property var inputs: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isStream || n.isSink !== false || !n.audio) continue
      if (String(n.name || "").indexOf(".monitor") >= 0) continue
      list.push(n)
    }
    return list
  }

  function toggleMute() {
    if (viaWpctl) { if (UntypedInput.known) UntypedInput.setMuted(!UntypedInput.muted) }
    else if (source && source.audio) source.audio.muted = !source.audio.muted
  }
  function setVolume(v) {
    var value = Math.max(0, Math.min(1, v))
    if (viaWpctl) { if (UntypedInput.known) UntypedInput.setVolume(value); return }
    if (source && source.audio) source.audio.volume = value
  }
  function appName(node) {
    var p = node.properties || {}
    return String(p["application.name"] || node.description || node.nickname || node.name || "")
  }

  visible: source !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened && panel.loadedContent) panel.loadedContent.rest()

  PwObjectTracker { objects: root.inputs.concat(root.activeStreams).concat(root.source ? [root.source] : []) }

  ShellIpc {
    target: "omarchy.microphone"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function mute(): void { root.toggleMute() }
  }

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    active: root.inUse
    tooltipText: root.muted ? Commons.I18n.t("bar.microphoneMuted") : (root.inUse ? Commons.I18n.t("bar.microphoneInUse") : Commons.I18n.t("bar.microphoneLive"))
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-shell shell toggle omarchy.audio") }
      else if (b === Qt.RightButton) root.toggleMute()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.setVolume(root.volume + (delta > 0 ? 0.05 : -0.05)) }
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
      title: root.t("mic.title")
      subtitle: root.source ? String(root.source.description || root.source.nickname || root.source.name || "") : ""
      glyph: root.muted ? "󰍭" : "󰍬"
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: M.sections({
          present: root.source !== null, muted: root.muted, volume: root.volume,
          inputs: root.inputs.map(function(n) {
            return { key: String(n.id), name: String(n.description || n.nickname || n.name || ""), current: root.source && n.id === root.source.id }
          }),
          apps: root.activeStreams.map(root.appName)
        }, root.t)
        onToggled: function(key, on) { if (key === "live" && on === root.muted) root.toggleMute() }
        onMoved: function(key, value) { if (key === "level") root.setVolume(value) }
        onPicked: function(key, value) {
          if (key !== "input") return
          for (var i = 0; i < root.inputs.length; i++)
            if (String(root.inputs[i].id) === value) Pipewire.preferredDefaultAudioSource = root.inputs[i]
        }
      }
    }
  }
}

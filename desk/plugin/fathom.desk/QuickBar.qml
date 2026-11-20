import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."
import "Desk.js" as D

// The bar's cluster (#14), as on Windows 11: Bluetooth, the network, volume
// and the battery in one button that opens Quick settings. `install.sh
// --desk` puts it where Omarchy's own four widgets were, and uninstall puts
// theirs back. The glyphs are theirs (Desk.js clusterGlyphs), so the bar
// looks the same; a part the machine hasn't got is left out.
//
// Click: Quick settings. Right-click: Quick settings on the Wi-Fi list.
// Middle-click: mute. Scroll: volume, 5% a step.
BarWidget {
  id: root
  moduleName: "fathom.desk"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Bluetooth.
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property int btConnected: {
    var list = Bluetooth.devices ? Bluetooth.devices.values : []
    var n = 0
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].connected) n++
    return n
  }

  // The network: Wi-Fi when connected, else Ethernet, else none.
  readonly property var devices: Networking.devices ? Networking.devices.values : []
  function connectedOf(type) {
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].type === type && devices[i].connected) return devices[i]
    return null
  }
  readonly property var wifi: connectedOf(DeviceType.Wifi)
  readonly property var wired: connectedOf(DeviceType.Wired)
  readonly property var wifiNet: {
    var list = wifi && wifi.networks ? wifi.networks.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].connected) return list[i]
    return null
  }

  // Volume.
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool hasSink: !!sink && !!sink.audio
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  function headphones(node) {
    if (!node) return false
    var p = node.properties || {}
    var blob = [node.name, node.description, node.nickname, p["device.icon-name"], p["device.product.name"],
                p["node.description"], p["node.nick"]].join(" ").toLowerCase()
    return blob.indexOf("headphone") !== -1 || blob.indexOf("headset") !== -1 || blob.indexOf("earbud") !== -1
  }

  // The battery.
  readonly property var power: UPower.displayDevice

  readonly property var glyphs: D.clusterGlyphs({
    bt: adapter ? { on: adapter.enabled, connected: btConnected } : null,
    net: wifi ? { kind: "wifi", signal: wifiNet ? Math.round((wifiNet.signalStrength || 0) * 100) : 0 }
      : (wired ? { kind: "ethernet" } : { kind: "none" }),
    audio: hasSink ? { volume: sink.audio.volume, muted: sink.audio.muted, headphones: headphones(sink) } : null,
    battery: power && power.isPresent ? { present: true, pct: power.percentage, onBattery: UPower.onBattery,
                                          full: power.state === UPowerDeviceState.FullyCharged } : null
  })

  readonly property string tooltip: {
    var parts = []
    if (wifi) parts.push(strings.t("bar.wifi").arg(wifiNet ? wifiNet.name : ""))
    else if (wired) parts.push(strings.t("bar.ethernet"))
    else parts.push(strings.t("bar.offline"))
    if (adapter) parts.push(!adapter.enabled ? strings.t("bar.btOff")
      : (btConnected > 0 ? strings.tn("bar.btDevices", btConnected).arg(btConnected) : strings.t("bar.btOn")))
    if (hasSink) parts.push(sink.audio.muted ? strings.t("bar.muted") : strings.t("bar.volume").arg(Math.round(sink.audio.volume * 100)))
    if (power && power.isPresent) parts.push(strings.t("bar.battery").arg(Math.round(power.percentage * 100)))
    return parts.join("\n")
  }

  // The slot's size is the button's, as the deck's pill does it.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function quick(page) {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "fathom.desk",
                             JSON.stringify(page ? { view: "quick", page: page } : { view: "quick" })])
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 10
    fixedWidth: root.vertical ? -1 : row.implicitWidth + Style.spaceReal(horizontalMargin) * 2
    fixedHeight: root.vertical ? row.implicitHeight + Style.spaceReal(verticalPadding) * 2 : -1
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.quick("wifi")
      else if (b === Qt.MiddleButton) { if (root.hasSink) root.sink.audio.muted = !root.sink.audio.muted }
      else root.quick("")
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(e) {
        if (!root.hasSink || e.angleDelta.y === 0) return
        var v = root.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)
        root.sink.audio.volume = Math.max(0, Math.min(1, Math.round(v * 20) / 20))
      }
    }

    Grid {
      id: row
      anchors.centerIn: parent
      flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
      columns: root.vertical ? 1 : Math.max(1, root.glyphs.length)
      rows: root.vertical ? Math.max(1, root.glyphs.length) : 1
      columnSpacing: Style.spaceReal(10)
      rowSpacing: Style.spaceReal(6)
      scale: button.pressScale

      Repeater {
        model: root.glyphs
        delegate: Text {
          required property var modelData
          textFormat: Text.PlainText
          text: String.fromCodePoint(modelData.cp)
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
        }
      }
    }
  }
}

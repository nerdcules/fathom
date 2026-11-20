import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import "."
import "Desk.js" as D
import "Version.js" as Build

// Quick settings (Super+Alt+A): Wi-Fi, Bluetooth, Focus, night light, stay
// awake and the power profile as tiles; this machine's IP addresses, each
// with a copy button; volume and brightness as sliders;
// the battery, lock and Omarchy's menu along the bottom. Under the bar at
// the top right, as on Windows.
//
// The chevrons on Wi-Fi and Bluetooth open their lists here, in place of
// the tiles (#14): networks to join, devices to connect or pair.
//
// Bluetooth, Wi-Fi networks and volume are Quickshell's own live objects; the rest comes
// from `fathom-desk settings`, read on opening and every 4 seconds while it
// shows, and changed through `fathom-desk set`.
Item {
  id: view

  property bool shown: false
  property var host: null
  signal done()

  readonly property var s: host ? host.settings : null
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property int btConnected: {
    var list = Bluetooth.devices ? Bluetooth.devices.values : []
    var n = 0
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].connected) n++
    return n
  }
  readonly property var battery: value("battery", null)
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool hasSink: !!sink && !!sink.audio

  // Values changed here show at once, before the next reading confirms them.
  property var pending: ({})
  function value(key, fallback) {
    if (pending[key] !== undefined) return pending[key]
    return s && s[key] !== undefined && s[key] !== null ? s[key] : fallback
  }
  function setValue(key, v) {
    var next = ({})
    for (var k in pending) next[k] = pending[k]
    next[key] = v
    pending = next
  }
  // A new reading replaces what was shown early. Later, not during the
  // binding that noticed the reading, or that binding would loop.
  onSChanged: Qt.callLater(function() { view.pending = ({}) })
  onShownChanged: {
    pending = ({}); askSsid = ""; failedSsid = ""; busySsid = ""; btFailed = ""
    page = shown && host ? host.quickPage : ""
  }

  // "" for the tiles, or "wifi" / "bluetooth" for a list.
  property string page: ""
  function openPage(name) { askSsid = ""; failedSsid = ""; btFailed = ""; page = name }

  // ------------------------------------------------ Wi-Fi list

  readonly property var wifiDevice: {
    var list = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].type === DeviceType.Wifi) return list[i]
    return null
  }
  readonly property var wifiNets: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  property string askSsid: ""      // the network a password is being typed for
  property string failedSsid: ""   // the last one that didn't connect
  property string busySsid: ""     // the one being connected or left

  function securityOf(net) {
    if (net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe) return "open"
    if (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap) return "enterprise"
    return "psk"
  }
  readonly property var wifiList: {
    var plain = []
    for (var i = 0; i < wifiNets.length; i++) {
      var n = wifiNets[i]
      if (!n) continue
      plain.push({ ssid: String(n.name || ""), signal: Number(n.signalStrength) || 0, known: n.known === true,
                   connected: n.connected === true, busy: n.stateChanging === true, security: securityOf(n) })
    }
    return D.wifiRows(plain, 30)
  }
  // The live network for a name: the connected one, or the strongest.
  function liveNet(ssid) {
    var best = null
    for (var i = 0; i < wifiNets.length; i++) {
      var n = wifiNets[i]
      if (!n || n.name !== ssid) continue
      if (n.connected) return n
      if (!best || (Number(n.signalStrength) || 0) > (Number(best.signalStrength) || 0)) best = n
    }
    return best
  }
  function wifiRow(ssid) {
    for (var i = 0; i < wifiList.length; i++) if (wifiList[i].ssid === ssid) return wifiList[i]
    return null
  }
  readonly property var wifiBars: [0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928]
  readonly property var wifiListRows: {
    var out = []
    for (var i = 0; i < wifiList.length; i++) {
      var r = wifiList[i]
      var detail = r.connected ? Skin.t("quick.list.connected")
        : r.ssid === failedSsid ? Skin.t("quick.list.failed")
        : r.known ? Skin.t("quick.list.saved")
        : r.security === "open" ? Skin.t("quick.list.open")
        : r.security === "enterprise" ? Skin.t("quick.list.enterprise") : Skin.t("quick.list.secured")
      out.push({ key: r.ssid, glyph: g(wifiBars[D.signalBars(r.signal)]), name: r.ssid, detail: detail,
                 active: r.connected, busy: r.busy || r.ssid === busySsid, ask: r.ssid === askSsid })
    }
    return out
  }
  function wifiPick(ssid) {
    var action = D.wifiAction(wifiRow(ssid))
    failedSsid = ""
    if (action === "password") { askSsid = askSsid === ssid ? "" : ssid; return }
    askSsid = ""
    if (action === "elsewhere") {
      done()
      Quickshell.execDetached(["omarchy-launch-tui", "nmtui", "connect"])
      return
    }
    var n = liveNet(ssid)
    if (!n) return
    busySsid = ssid
    wifiWatch.target = n
    if (action === "disconnect") n.disconnect()
    else n.connect()
  }
  function wifiPassword(ssid, password) {
    if (password === "") return
    var n = liveNet(ssid)
    askSsid = ""
    if (!n) return
    failedSsid = ""
    busySsid = ssid
    wifiWatch.target = n
    n.connectWithPsk(password)
  }
  Connections {
    id: wifiWatch
    target: null
    ignoreUnknownSignals: true
    function onConnectionFailed(reason) {
      var ssid = view.busySsid
      view.failedSsid = ssid
      view.busySsid = ""
      // A wrong password: ask again.
      var row = view.wifiRow(ssid)
      if (row && row.security === "psk") view.askSsid = ssid
    }
    function onConnectedChanged() { if (wifiWatch.target) view.busySsid = "" }
  }
  // Scan for networks while the list shows.
  Binding {
    target: view.wifiDevice
    property: "scannerEnabled"
    value: true
    when: view.shown && view.page === "wifi" && !!view.wifiDevice
    restoreMode: Binding.RestoreValue
  }

  // ------------------------------------------------ Bluetooth list

  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  property string btBusy: ""       // the device an action is running for
  property string btFailed: ""     // the last one an action failed for
  readonly property var btList: {
    var plain = []
    for (var i = 0; i < btDevices.length; i++) {
      var d = btDevices[i]
      if (!d) continue
      plain.push({ address: String(d.address || ""), name: String(d.name || d.deviceName || ""),
                   connected: d.connected === true, paired: d.paired === true || d.bonded === true || d.trusted === true,
                   busy: d.address === btBusy || d.pairing === true,
                   battery: d.batteryAvailable ? d.battery : null })
    }
    return D.bluetoothRows(plain, 12)
  }
  readonly property var btListRows: {
    var out = []
    var section = ""
    for (var i = 0; i < btList.length; i++) {
      var r = btList[i]
      if (r.section !== section) {
        section = r.section
        out.push({ header: Skin.t("quick.list." + section) })
      }
      var detail = r.address === btFailed ? Skin.t("quick.list.failed")
        : r.connected ? (r.battery !== null ? Skin.t("quick.list.connectedBattery").arg(Math.round(r.battery * 100)) : Skin.t("quick.list.connected"))
        : r.paired ? Skin.t("quick.list.notConnected") : Skin.t("quick.list.pair")
      out.push({ key: r.address, glyph: g(r.connected ? 0xF00B1 : 0xF00AF), name: r.name !== "" ? r.name : r.address,
                 detail: detail, active: r.connected, busy: r.busy, ask: false })
    }
    return out
  }
  function btPick(address) {
    if (btProc.running) return
    var row = null
    for (var i = 0; i < btList.length; i++) if (btList[i].address === address) row = btList[i]
    var action = D.bluetoothAction(row)
    if (!action) return
    btFailed = ""
    btBusy = address
    btProc.command = ["omarchy-bluetooth-device", action, address]
    btProc.running = true
  }
  Process {
    id: btProc
    onExited: function(code) {
      if (code !== 0) view.btFailed = view.btBusy
      view.btBusy = ""
    }
  }
  // Look for nearby devices while the list shows.
  Binding {
    target: view.adapter
    property: "discovering"
    value: true
    when: view.shown && view.page === "bluetooth" && !!view.adapter && view.adapter.enabled
    restoreMode: Binding.RestoreValue
  }

  function g(cp) { return String.fromCodePoint(cp) }

  // What to call an interface: Wi-Fi, Ethernet, Tailscale, VPN, or its name.
  function kindName(row) {
    return row.kind === "other" ? row.name : Skin.t("quick.net." + row.kind)
  }

  function toggle(what, on) {
    host.setSetting(what, on ? "on" : "off")
  }

  function key(e) {
    if (e.key !== Qt.Key_Escape) return
    if (page !== "") { if (askSsid !== "") askSsid = ""; else page = "" }
    else done()
    e.accepted = true
  }

  PwObjectTracker { objects: view.sink ? [view.sink] : [] }

  // A click anywhere else closes it.
  MouseArea { anchors.fill: parent; onClicked: view.done() }

  Glass {
    id: panel
    readonly property real barTop: view.host && view.host.monitor && Array.isArray(view.host.monitor.reserved)
      ? Number(view.host.monitor.reserved[1]) || 0 : 0
    anchors { right: parent.right; rightMargin: 12 * Skin.u; top: parent.top; topMargin: barTop + 10 * Skin.u }
    width: 420 * Skin.u
    height: (view.page === "" ? body.implicitHeight : listPage.implicitHeight) + 36 * Skin.u
    opacity: view.shown ? 1 : 0
    transform: Translate { y: view.shown ? 0 : -10 * Skin.u; Behavior on y { NumberAnimation { duration: Skin.ms(160); easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: Skin.ms(140) } }

    MouseArea { anchors.fill: parent }

    QuickList {
      id: listPage
      visible: view.page !== ""
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 * Skin.u }
      readonly property bool isWifi: view.page === "wifi"
      readonly property var wifi: view.value("wifi", null)
      title: isWifi ? Skin.t("quick.wifi") : Skin.t("quick.bluetooth")
      on: isWifi ? (!!wifi && wifi.on) : (!!view.adapter && view.adapter.enabled)
      canToggle: isWifi ? wifi !== null : !!view.adapter
      rows: !on ? [] : (isWifi ? view.wifiListRows : view.btListRows)
      emptyText: isWifi
        ? (wifi === null || !view.wifiDevice ? Skin.t("quick.list.noWifi") : (!on ? Skin.t("quick.list.wifiOff") : Skin.t("quick.list.searching")))
        : (!view.adapter ? Skin.t("quick.list.noBluetooth") : (!on ? Skin.t("quick.list.bluetoothOff") : Skin.t("quick.list.searching")))
      note: isWifi && on && rows.length > 0 ? Skin.t("quick.list.wifiNote") : ""
      askLabel: Skin.t("quick.list.password")
      connectLabel: Skin.t("quick.list.connect")
      cancelLabel: Skin.t("quick.list.cancel")
      workingLabel: Skin.t("quick.list.working")
      onBack: { view.askSsid = ""; view.page = "" }
      onToggled: {
        if (isWifi) {
          var next = { on: !on, ssid: on ? "" : (wifi ? wifi.ssid : ""), signal: 0 }
          view.setValue("wifi", next)
          view.toggle("wifi", !on)
        } else if (view.adapter) view.adapter.enabled = !view.adapter.enabled
      }
      onPicked: function(key) { if (isWifi) view.wifiPick(key); else view.btPick(key) }
      onPasswordGiven: function(key, password) { view.wifiPassword(key, password) }
      onAskCancelled: view.askSsid = ""
    }

    Column {
      id: body
      visible: view.page === ""
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 * Skin.u }
      spacing: 16 * Skin.u

      Grid {
        id: tiles
        width: parent.width
        columns: 3
        spacing: 10 * Skin.u
        readonly property real tileW: (width - spacing * (columns - 1)) / columns

        QuickTile {
          width: tiles.tileW
          readonly property var wifi: view.value("wifi", null)
          available: wifi !== null
          on: !!wifi && wifi.on
          glyph: on ? view.g(0xF05A9) : view.g(0xF05AA)
          title: Skin.t("quick.wifi")
          detail: !available ? Skin.t("quick.unavailable") : (!on ? Skin.t("quick.off") : (wifi.ssid !== "" ? wifi.ssid : Skin.t("quick.notConnected")))
          moreable: true
          onToggled: {
            var next = { on: !on, ssid: on ? "" : (wifi ? wifi.ssid : ""), signal: 0 }
            view.setValue("wifi", next)
            view.toggle("wifi", !on)
          }
          onMore: view.openPage("wifi")
        }

        QuickTile {
          width: tiles.tileW
          available: !!view.adapter
          on: !!view.adapter && view.adapter.enabled
          glyph: on ? view.g(0xF00AF) : view.g(0xF00B2)
          title: Skin.t("quick.bluetooth")
          detail: !available ? Skin.t("quick.unavailable") : (!on ? Skin.t("quick.off")
            : (view.btConnected > 0 ? Skin.tn("quick.devices", view.btConnected).arg(view.btConnected) : Skin.t("quick.on")))
          moreable: true
          onToggled: if (view.adapter) view.adapter.enabled = !view.adapter.enabled
          onMore: view.openPage("bluetooth")
        }

        QuickTile {
          width: tiles.tileW
          readonly property var dnd: view.value("focus", null)
          available: dnd !== null
          on: dnd === true
          glyph: view.g(0xF009B)
          title: Skin.t("quick.focus")
          detail: on ? Skin.t("quick.focusOn") : Skin.t("quick.off")
          onToggled: { view.setValue("focus", !on); view.toggle("focus", !on) }
        }

        QuickTile {
          width: tiles.tileW
          readonly property var lit: view.value("nightlight", null)
          available: lit !== null
          on: lit === true
          glyph: view.g(0xF0594)
          title: Skin.t("quick.nightlight")
          detail: on ? Skin.t("quick.on") : Skin.t("quick.off")
          onToggled: { view.setValue("nightlight", !on); view.toggle("nightlight", !on) }
        }

        QuickTile {
          width: tiles.tileW
          on: view.value("awake", false) === true
          available: !!view.s
          glyph: view.g(0xF0176)
          title: Skin.t("quick.awake")
          detail: on ? Skin.t("quick.awakeOn") : Skin.t("quick.off")
          onToggled: { view.setValue("awake", !on); view.toggle("awake", !on) }
        }

        QuickTile {
          width: tiles.tileW
          readonly property var profile: view.value("profile", null)
          available: profile !== null && Array.isArray(profile.all) && profile.all.length > 0
          on: available && profile.current === "performance"
          glyph: view.g(0xF04C5)
          title: Skin.t("quick.power")
          detail: available ? Skin.t("quick.profile." + profile.current) : Skin.t("quick.unavailable")
          onToggled: {
            var next = D.nextProfile(profile.current, profile.all)
            if (!next) return
            view.setValue("profile", { current: next, all: profile.all })
            view.host.setSetting("profile", next)
          }
        }
      }

      // This machine's addresses, from `fathom-desk settings`: each
      // interface that's up, IPv4 then IPv6, each with a copy button.
      Column {
        id: addressList
        width: parent.width
        spacing: 2 * Skin.u
        readonly property var rows: D.addressRows(view.value("addresses", null), 6)
        property string copied: ""
        visible: rows.length > 0

        Timer { id: copiedTimer; interval: 1500; onTriggered: addressList.copied = "" }

        Repeater {
          model: addressList.rows
          delegate: Item {
            id: addressRow
            required property var modelData
            width: addressList.width
            height: 30 * Skin.u
            Label {
              id: kindLabel
              anchors { left: parent.left; verticalCenter: parent.verticalCenter }
              width: 96 * Skin.u
              text: addressRow.modelData.first ? view.kindName(addressRow.modelData) : ""
              color: Skin.dim
              font.pixelSize: 12 * Skin.u
              elide: Text.ElideRight
            }
            Label {
              anchors { left: kindLabel.right; right: copyButton.left; rightMargin: 8 * Skin.u; verticalCenter: parent.verticalCenter }
              text: addressRow.modelData.address
              font.pixelSize: 13 * Skin.u
              elide: Text.ElideMiddle
            }
            Button {
              id: copyButton
              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              readonly property bool done: addressList.copied === addressRow.modelData.address
              glyph: done ? view.g(0xF012C) : view.g(0xF018F)
              Accessible.name: Skin.t("quick.copy").arg(addressRow.modelData.address)
              onClicked: {
                Quickshell.execDetached(["wl-copy", addressRow.modelData.address])
                addressList.copied = addressRow.modelData.address
                copiedTimer.restart()
              }
            }
          }
        }
      }

      // Volume.
      SliderRow {
        width: parent.width
        enabled: view.hasSink
        glyph: !view.hasSink || view.sink.audio.muted ? view.g(0xF0581) : view.g(0xF057E)
        glyphTip: Skin.t("quick.mute")
        value: view.hasSink ? Math.min(1, view.sink.audio.volume) : 0
        label: view.hasSink ? (view.sink.audio.muted ? Skin.t("quick.muted") : Math.round(view.sink.audio.volume * 100) + "%") : "–"
        onGlyphClicked: if (view.hasSink) view.sink.audio.muted = !view.sink.audio.muted
        onMoved: function(v) { if (view.hasSink) view.sink.audio.volume = v }
      }

      // Brightness: sent as it moves, at most every 120 ms.
      SliderRow {
        id: bright
        width: parent.width
        readonly property var level: view.value("brightness", null)
        enabled: level !== null
        glyph: view.g(0xF00E0)
        value: level !== null ? level / 100 : 0
        label: level !== null ? Math.round(level) + "%" : "–"
        property int want: -1
        onMoved: function(v) {
          var pct = D.clampPercent(v * 100)
          if (pct === null) return
          view.setValue("brightness", pct)
          want = pct
          if (!throttle.running) { throttle.start(); view.host.setSetting("brightness", pct); want = -1 }
        }
        Timer {
          id: throttle
          interval: 120
          onTriggered: if (bright.want > 0) { view.host.setSetting("brightness", bright.want); bright.want = -1 }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Skin.faint }

      // Battery, lock, menu.
      Item {
        width: parent.width
        height: 32 * Skin.u
        Row {
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          spacing: 8 * Skin.u
          visible: !!view.battery && view.battery.pct !== null
          Label {
            text: view.g(0xF0079)
            color: view.battery && view.battery.pct !== null && view.battery.pct <= 15 ? Skin.urgent : Skin.accent
            font.pixelSize: 16 * Skin.u
          }
          Label {
            text: view.battery ? Skin.t("quick.battery").arg(view.battery.pct).arg(view.battery.status) : ""
            font.pixelSize: 13 * Skin.u
          }
        }
        Row {
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          spacing: 8 * Skin.u
          Button {
            glyph: view.g(0xF033E)
            text: Skin.t("quick.lock")
            onClicked: { view.done(); Quickshell.execDetached(["omarchy-system-lock"]) }
          }
          Button {
            glyph: view.g(0xF0493)
            text: Skin.t("quick.menu")
            onClicked: { view.done(); Quickshell.execDetached(["omarchy-menu", "summon", "root"]) }
          }
        }
      }

      // Fathom's version, as the deck and Start show it.
      Label {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        text: "Fathom " + Build.text
        color: Skin.dim
        font.pixelSize: 11 * Skin.u
      }
    }
  }
}

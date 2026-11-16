import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "."
import "Desk.js" as D

// Quick settings (Super+Alt+A): Wi-Fi, Bluetooth, Focus, night light, stay
// awake and the power profile as tiles; volume and brightness as sliders;
// the battery, lock and Omarchy's menu along the bottom. Under the bar at
// the top right, as on Windows.
//
// Bluetooth and volume are Quickshell's own live objects; the rest comes
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
  onShownChanged: pending = ({})

  function g(cp) { return String.fromCodePoint(cp) }

  function toggle(what, on) {
    host.setSetting(what, on ? "on" : "off")
  }

  // Open one of Omarchy's own panels for the details, closing this first.
  function more(pluginId) {
    done()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", pluginId])
  }

  function key(e) {
    if (e.key === Qt.Key_Escape) { done(); e.accepted = true }
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
    height: body.implicitHeight + 36 * Skin.u
    opacity: view.shown ? 1 : 0
    transform: Translate { y: view.shown ? 0 : -10 * Skin.u; Behavior on y { NumberAnimation { duration: Skin.ms(160); easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: Skin.ms(140) } }

    MouseArea { anchors.fill: parent }

    Column {
      id: body
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
          onMore: view.more("omarchy.network")
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
          onMore: view.more("omarchy.bluetooth")
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
    }
  }
}

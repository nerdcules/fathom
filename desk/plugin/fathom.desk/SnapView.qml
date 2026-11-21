import QtQuick
import "kit"
import "."
import "Desk.js" as D

// Snap layouts (Super+Z): six layouts across the top of the screen. Hover a
// zone to see where the window would go, at full size; click it to put the
// window there. Then Snap assist offers the workspace's other windows for
// the zones left, one zone at a time, as on Windows; Esc stops.
//
// A snapped window floats at the zone's size and place, so this works on
// tiled workspaces as well as floating ones; "Back to tiling" undoes it.
//
// Keys: arrows pick a zone, Enter snaps, Esc closes.
Item {
  id: view

  property bool shown: false
  property var host: null
  signal done()

  property string target: ""         // the window being snapped
  property int cursor: 0             // index into the zone order, for the keys
  property int hoverLayout: -1
  property int hoverZone: -1
  // Snap assist: the layout chosen and the zones still to fill.
  property int assistLayout: -1
  property var assistZones: []
  property var placed: []            // addresses already snapped this time

  readonly property var order: D.zoneOrder()
  readonly property var area: host ? D.usableArea(host.monitor, host.state ? host.state.gapsOut : 0) : null
  readonly property real gapsIn: host && host.state ? Number(host.state.gapsIn) || 0 : 0
  readonly property var targetWin: {
    var all = host ? host.windows : []
    for (var i = 0; i < all.length; i++) if (all[i].address === target) return all[i]
    return null
  }
  readonly property var candidates: {
    if (assistLayout < 0 || !host) return []
    var all = host.windows, out = []
    for (var i = 0; i < all.length; i++) {
      var w = all[i]
      if (w.minimized || w.workspace !== host.currentWorkspace || placed.indexOf(w.address) !== -1) continue
      out.push(w)
    }
    return out
  }

  function reset() {
    target = ""
    assistLayout = -1
    assistZones = []
    placed = []
    hoverLayout = -1
    hoverZone = -1
    cursor = 0
  }

  // The focused window, from the reading taken as the view opened; the
  // first one at hand may be from before.
  property bool settled: false
  function begin() { reset(); settled = false; target = host ? host.activeAddress : "" }
  onShownChanged: if (shown) begin()
  Component.onCompleted: if (shown) begin()
  // The window list is read as the view opens; take the focused window
  // from the fresh reading if there wasn't one before.
  Connections {
    target: view.host
    function onStateChanged() {
      if (!view.shown || view.settled || view.assistLayout >= 0) return
      view.target = view.host.activeAddress
      view.settled = true
    }
  }

  // Where a zone falls, in this overlay's coordinates.
  function local(rect) {
    var m = host ? host.monitor : null
    if (!rect || !m) return null
    return { x: rect.x - (Number(m.x) || 0), y: rect.y - (Number(m.y) || 0), width: rect.width, height: rect.height }
  }

  function rectFor(l, z) {
    if (!area || l < 0 || z < 0) return null
    return D.zoneRect(D.LAYOUTS[l].zones[z], area, gapsIn)
  }

  function snapTo(address, l, z) {
    var rect = rectFor(l, z)
    var cmds = D.snap(address, rect)
    if (cmds.length === 0) return false
    host.dispatch(cmds)
    placed = placed.concat([address])
    return true
  }

  function choose(l, z) {
    if (!snapTo(target, l, z)) return
    var rest = []
    for (var i = 0; i < D.LAYOUTS[l].zones.length; i++) if (i !== z) rest.push(i)
    assistLayout = l
    assistZones = rest
    // Nothing to offer: done.
    Qt.callLater(function() { if (view.assistZones.length === 0 || view.candidates.length === 0) view.done() })
  }

  function assistPick(win) {
    if (assistZones.length === 0) return
    snapTo(win.address, assistLayout, assistZones[0])
    assistZones = assistZones.slice(1)
    if (assistZones.length === 0) done()
    else Qt.callLater(function() { if (view.candidates.length === 0) view.done() })
  }

  function key(e) {
    if (e.key === Qt.Key_Escape) done()
    else if (assistLayout >= 0) return
    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) cursor = (cursor + 1) % order.length
    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) cursor = (cursor - 1 + order.length) % order.length
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) choose(order[cursor][0], order[cursor][1])
    else return
    e.accepted = true
  }

  readonly property int showLayout: hoverLayout >= 0 ? hoverLayout : (assistLayout < 0 ? order[cursor][0] : -1)
  readonly property int showZone: hoverLayout >= 0 ? hoverZone : (assistLayout < 0 ? order[cursor][1] : -1)

  // A light veil, so the windows stay in view. A click on it closes.
  Rectangle {
    anchors.fill: parent
    color: Skin.tint(Skin.bg, view.assistLayout >= 0 ? 0.55 : 0.25)
    MouseArea { anchors.fill: parent; onClicked: view.done() }
  }

  // Where the window would go, at full size.
  Rectangle {
    readonly property var r: view.local(view.rectFor(view.showLayout, view.showZone))
    visible: !!r && view.assistLayout < 0
    x: r ? r.x : 0
    y: r ? r.y : 0
    width: r ? r.width : 0
    height: r ? r.height : 0
    radius: 12 * Skin.u
    color: Skin.tint(Skin.accent, 0.16)
    border.width: 2
    border.color: Skin.accent
    Behavior on x { NumberAnimation { duration: Skin.ms(110); easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: Skin.ms(110); easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Skin.ms(110); easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Skin.ms(110); easing.type: Easing.OutCubic } }
  }

  // The picker.
  Glass {
    id: picker
    visible: view.assistLayout < 0
    anchors { top: parent.top; topMargin: 70 * Skin.u; horizontalCenter: parent.horizontalCenter }
    width: content.width + 36 * Skin.u
    height: content.height + 32 * Skin.u
    MouseArea { anchors.fill: parent }

    Column {
      id: content
      anchors.centerIn: parent
      spacing: 14 * Skin.u

      Label {
        width: Math.min(implicitWidth, layouts.width)
        text: view.targetWin ? Skin.t("snap.title").arg(view.targetWin.title !== "" ? view.targetWin.title : view.targetWin.appClass)
          : Skin.t("snap.noWindow")
        font.pixelSize: 15 * Skin.u
        font.weight: Font.DemiBold
      }

      Row {
        id: layouts
        spacing: 14 * Skin.u
        enabled: !!view.targetWin
        opacity: enabled ? 1 : 0.4

        Repeater {
          model: D.LAYOUTS.length
          delegate: Column {
            id: layoutCell
            required property int index
            spacing: 6 * Skin.u
            Rectangle {
              id: screenPic
              width: 128 * Skin.u
              height: width / (view.area ? view.area.width / view.area.height : 1.6)
              radius: 8 * Skin.u
              color: Skin.tint(Skin.fg, 0.05)
              border.width: 1
              border.color: Skin.tint(Skin.fg, 0.16)
              Repeater {
                model: D.LAYOUTS[layoutCell.index].zones
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  readonly property bool lit: view.showLayout === layoutCell.index && view.showZone === index
                  x: 4 * Skin.u + modelData[0] * (screenPic.width - 8 * Skin.u) + 2 * Skin.u
                  y: 4 * Skin.u + modelData[1] * (screenPic.height - 8 * Skin.u) + 2 * Skin.u
                  width: modelData[2] * (screenPic.width - 8 * Skin.u) - 4 * Skin.u
                  height: modelData[3] * (screenPic.height - 8 * Skin.u) - 4 * Skin.u
                  radius: 5 * Skin.u
                  color: lit ? Skin.accent : Skin.tint(Skin.fg, zoneMouse.containsMouse ? 0.3 : 0.16)
                  MouseArea {
                    id: zoneMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { view.hoverLayout = layoutCell.index; view.hoverZone = parent.index }
                    onExited: if (view.hoverLayout === layoutCell.index && view.hoverZone === parent.index) { view.hoverLayout = -1; view.hoverZone = -1 }
                    onClicked: view.choose(layoutCell.index, parent.index)
                  }
                }
              }
            }
            Label {
              width: screenPic.width
              horizontalAlignment: Text.AlignHCenter
              text: Skin.t("snap.layout." + D.LAYOUTS[layoutCell.index].id)
              color: Skin.dim
              font.pixelSize: 11 * Skin.u
            }
          }
        }
      }

      Row {
        spacing: 10 * Skin.u
        Pill {
          visible: !!view.targetWin && view.targetWin.floating
          text: Skin.t("snap.tile")
          onClicked: { view.host.dispatch(D.tile(view.target)); view.done() }
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          text: Skin.t("snap.hint")
          color: Skin.dim
          font.pixelSize: 11 * Skin.u
        }
      }
    }
  }

  // Snap assist: the next zone to fill, with the windows that could go there.
  Item {
    id: assist
    visible: view.assistLayout >= 0 && view.assistZones.length > 0 && view.candidates.length > 0
    readonly property var r: visible ? view.local(view.rectFor(view.assistLayout, view.assistZones[0])) : null
    x: r ? r.x : 0
    y: r ? r.y : 0
    width: r ? r.width : 0
    height: r ? r.height : 0

    Rectangle {
      anchors.fill: parent
      radius: 14 * Skin.u
      color: Skin.tint(Skin.bg, Skin.panelAlpha)
      border.width: 2
      border.color: Skin.accent
      MouseArea { anchors.fill: parent }
    }
    Label {
      id: assistTitle
      anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 * Skin.u }
      text: Skin.t("snap.assist")
      font.pixelSize: 15 * Skin.u
      font.weight: Font.DemiBold
    }
    Item {
      anchors { left: parent.left; right: parent.right; top: assistTitle.bottom; bottom: parent.bottom; margins: 16 * Skin.u }
      readonly property var fitted: D.gridFit(view.candidates.length, width, height, 1.35, 12 * Skin.u)
      Grid {
        anchors.centerIn: parent
        columns: parent.fitted.columns
        spacing: 12 * Skin.u
        Repeater {
          model: view.candidates
          delegate: WindowCard {
            required property var modelData
            width: parent.parent.fitted.cardWidth
            height: parent.parent.fitted.cardHeight
            win: modelData
            toplevel: view.host ? view.host.toplevelFor(modelData.address) : null
            live: false
            onClicked: view.assistPick(modelData)
          }
        }
      }
    }
  }
}

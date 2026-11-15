import QtQuick
import Quickshell
import "."
import "Desk.js" as D

// Task view (Super+Tab): the windows of a workspace as large live cards,
// and every workspace along the bottom. Hover a workspace to see its
// windows; click one to go there. Click a window to bring it forward, drag
// it onto a workspace to move it there (or onto New to give it a new one),
// or close it with its x or a middle-click.
//
// Keys: arrows pick a window, Enter brings it forward, Delete closes it,
// Page Up / Page Down (or Ctrl+arrows) look at another workspace, 1 to 9 go
// to that workspace, Esc closes Task view.
Item {
  id: view

  property bool shown: false
  property var host: null
  signal done()

  property int shownWorkspace: 0
  property int selected: 0
  property var dragging: null                 // the window being dragged
  property point dragAt: Qt.point(0, 0)

  readonly property var workspaces: host ? host.workspaces : []
  readonly property var windows: {
    var all = host ? host.windows : []
    var out = []
    for (var i = 0; i < all.length; i++) if (all[i].workspace === shownWorkspace) out.push(all[i])
    return out
  }
  readonly property var mon: host ? host.monitor : null
  readonly property real aspect: mon && mon.width > 0 && mon.height > 0 ? mon.width / mon.height : 16 / 10

  // Until you look at another workspace, show the one on screen, as read
  // fresh when Task view opened (the first reading may be from before).
  property bool following: true
  Connections {
    target: view.host
    function onCurrentWorkspaceChanged() { if (view.following) view.shownWorkspace = view.host.currentWorkspace }
  }

  function begin() {
    following = true
    shownWorkspace = host ? host.currentWorkspace : 0
    selected = 0
    dragging = null
  }
  onShownChanged: if (shown) begin()
  Component.onCompleted: if (shown) begin()
  onWindowsChanged: if (selected >= windows.length) selected = Math.max(0, windows.length - 1)

  function bring(win) {
    host.activate(win)
    done()
  }

  function goTo(id) {
    host.dispatch([D.focusWorkspace(id)])
    done()
  }

  function closeWin(win) {
    host.dispatch([D.closeWindow(win.address)])
  }

  function lookAt(delta) {
    var ids = workspaces.map(function(w) { return w.id })
    var i = ids.indexOf(shownWorkspace)
    if (ids.length === 0) return
    i = i === -1 ? 0 : (i + delta + ids.length) % ids.length
    following = false
    shownWorkspace = ids[i]
    selected = 0
  }

  function key(e) {
    var cols = Math.max(1, fit.columns)
    var ctrl = (e.modifiers & Qt.ControlModifier) !== 0
    if (e.key === Qt.Key_Escape) done()
    else if (e.key === Qt.Key_PageDown || (ctrl && e.key === Qt.Key_Right)) lookAt(1)
    else if (e.key === Qt.Key_PageUp || (ctrl && e.key === Qt.Key_Left)) lookAt(-1)
    else if (e.key === Qt.Key_Right) selected = Math.min(windows.length - 1, selected + 1)
    else if (e.key === Qt.Key_Left) selected = Math.max(0, selected - 1)
    else if (e.key === Qt.Key_Down) selected = Math.min(windows.length - 1, selected + cols)
    else if (e.key === Qt.Key_Up) selected = Math.max(0, selected - cols)
    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && windows.length > 0) bring(windows[selected])
    else if (e.key === Qt.Key_Delete && windows.length > 0) closeWin(windows[selected])
    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) goTo(e.key - Qt.Key_0)
    else return
    e.accepted = true
  }

  // The workspace tile under a point on the screen, or null.
  function tileAt(sx, sy) {
    for (var i = 0; i < tiles.count; i++) {
      var t = tiles.itemAt(i)
      var p = t.mapFromItem(null, sx, sy)
      if (p.x >= 0 && p.y >= 0 && p.x <= t.width && p.y <= t.height) return t
    }
    var n = newTile.mapFromItem(null, sx, sy)
    if (n.x >= 0 && n.y >= 0 && n.x <= newTile.width && n.y <= newTile.height) return newTile
    return null
  }

  // A dimmed screen; a click on it closes Task view.
  Rectangle {
    anchors.fill: parent
    color: Skin.tint(Skin.bg, Skin.scrimAlpha)
    opacity: view.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Skin.ms(160) } }
    MouseArea { anchors.fill: parent; onClicked: view.done() }
  }

  // Heading: which workspace these windows are on.
  Label {
    id: heading
    anchors { top: parent.top; topMargin: 56 * Skin.u; horizontalCenter: parent.horizontalCenter }
    text: view.shownWorkspace === (view.host ? view.host.currentWorkspace : -1)
      ? Skin.t("tasks.thisWorkspace").arg(view.shownWorkspace)
      : Skin.t("tasks.workspace").arg(view.shownWorkspace)
    font.pixelSize: 20 * Skin.u
    font.weight: Font.DemiBold
  }
  Label {
    anchors { top: heading.bottom; topMargin: 4 * Skin.u; horizontalCenter: parent.horizontalCenter }
    text: Skin.tn("tasks.count", view.windows.length).arg(view.windows.length)
    color: Skin.dim
    font.pixelSize: 13 * Skin.u
  }

  // The windows.
  Item {
    id: area
    anchors {
      left: parent.left; right: parent.right; top: heading.bottom; bottom: strip.top
      leftMargin: 60 * Skin.u; rightMargin: 60 * Skin.u; topMargin: 44 * Skin.u; bottomMargin: 30 * Skin.u
    }
    readonly property real gap: 22 * Skin.u
    readonly property var fitted: D.gridFit(view.windows.length, width, height, view.aspect * 0.92, gap)

    Label {
      anchors.centerIn: parent
      visible: view.windows.length === 0
      text: Skin.t("tasks.empty")
      color: Skin.dim
    }

    Grid {
      id: grid
      anchors.centerIn: parent
      columns: area.fitted.columns
      spacing: area.gap
      Repeater {
        model: view.windows
        delegate: WindowCard {
          required property var modelData
          required property int index
          width: area.fitted.cardWidth
          height: area.fitted.cardHeight
          win: modelData
          toplevel: view.host ? view.host.toplevelFor(modelData.address) : null
          selected: index === view.selected
          live: view.shown
          closable: true
          opacity: view.dragging && view.dragging.address === modelData.address ? 0.35 : 1
          onClicked: view.bring(modelData)
          onCloseRequested: view.closeWin(modelData)
          onPressed: function(x, y) { view.selected = index }
          onMoved: function(x, y) { view.dragging = modelData; view.dragAt = Qt.point(x, y) }
          onReleased: function(x, y) {
            var t = view.tileAt(x, y)
            if (t && view.dragging) {
              var id = t.isNew ? D.freeWorkspace(view.workspaces) : t.wsId
              if (id !== view.dragging.workspace || view.dragging.minimized)
                view.host.dispatch([D.moveToWorkspace(view.dragging.address, id, false)])
            }
            view.dragging = null
          }
        }
      }
    }
  }
  QtObject { id: fit; readonly property int columns: area.fitted.columns }

  // The workspaces, along the bottom.
  Row {
    id: strip
    anchors { bottom: parent.bottom; bottomMargin: 34 * Skin.u; horizontalCenter: parent.horizontalCenter }
    spacing: 16 * Skin.u
    readonly property real tileH: 96 * Skin.u
    readonly property real tileW: tileH * view.aspect

    Repeater {
      id: tiles
      model: view.workspaces
      delegate: Rectangle {
        id: tile
        required property var modelData
        readonly property int wsId: modelData.id
        readonly property bool isNew: false
        readonly property bool current: view.host && wsId === view.host.currentWorkspace
        readonly property bool target: !!view.dragging && view.tileAt(view.dragAt.x, view.dragAt.y) === tile
        width: strip.tileW
        height: strip.tileH + 26 * Skin.u
        radius: 12 * Skin.u
        color: target ? Skin.tint(Skin.accent, 0.28) : (tileMouse.containsMouse || wsId === view.shownWorkspace ? Skin.tint(Skin.fg, 0.1) : Skin.tint(Skin.bg, 0.7))
        border.width: current || target ? 2 : 1
        border.color: current || target ? Skin.accent : Skin.tint(Skin.fg, 0.14)

        // A small picture of the workspace: its windows where they sit.
        Rectangle {
          id: mini
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 * Skin.u }
          height: strip.tileH - 12 * Skin.u
          radius: 8 * Skin.u
          color: Skin.tint(Skin.bg, 0.9)
          clip: true
          Repeater {
            model: {
              var all = view.host ? view.host.windows : []
              return all.filter(function(w) { return w.workspace === tile.wsId && !w.minimized })
            }
            delegate: Rectangle {
              required property var modelData
              readonly property var r: D.miniRect(modelData, view.mon)
              visible: r !== null
              x: r ? r.x * mini.width : 0
              y: r ? r.y * mini.height : 0
              width: r ? Math.max(4, r.w * mini.width - 2) : 0
              height: r ? Math.max(4, r.h * mini.height - 2) : 0
              radius: 3 * Skin.u
              color: Skin.tint(Skin.accent, 0.16)
              border.width: 1
              border.color: Skin.tint(Skin.accent, 0.45)
            }
          }
        }
        Label {
          anchors { bottom: parent.bottom; bottomMargin: 5 * Skin.u; horizontalCenter: parent.horizontalCenter }
          text: Skin.t("tasks.tile").arg(tile.wsId)
          font.pixelSize: 12 * Skin.u
          font.weight: tile.current ? Font.DemiBold : Font.Normal
        }
        MouseArea {
          id: tileMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: if (!view.dragging) { view.following = false; view.shownWorkspace = tile.wsId; view.selected = 0 }
          onClicked: view.goTo(tile.wsId)
        }
      }
    }

    // A new, empty workspace.
    Rectangle {
      id: newTile
      readonly property bool isNew: true
      readonly property int wsId: D.freeWorkspace(view.workspaces)
      readonly property bool target: !!view.dragging && view.tileAt(view.dragAt.x, view.dragAt.y) === newTile
      width: strip.tileH
      height: strip.tileH + 26 * Skin.u
      radius: 12 * Skin.u
      color: target ? Skin.tint(Skin.accent, 0.28) : (newMouse.containsMouse ? Skin.tint(Skin.fg, 0.1) : "transparent")
      border.width: target ? 2 : 1
      border.color: target ? Skin.accent : Skin.tint(Skin.fg, 0.25)
      Label {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 * Skin.u }
        text: "+"
        color: Skin.accent
        font.pixelSize: 30 * Skin.u
      }
      Label {
        anchors { bottom: parent.bottom; bottomMargin: 5 * Skin.u; horizontalCenter: parent.horizontalCenter }
        text: Skin.t("tasks.new")
        font.pixelSize: 12 * Skin.u
      }
      MouseArea {
        id: newMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: view.goTo(newTile.wsId)
      }
    }
  }

  // What's being dragged, following the pointer.
  Rectangle {
    visible: !!view.dragging
    x: view.dragAt.x - width / 2
    y: view.dragAt.y - height / 2
    width: 200 * Skin.u
    height: 44 * Skin.u
    radius: 12 * Skin.u
    color: Skin.tint(Skin.bg, 0.95)
    border.width: 1
    border.color: Skin.accent
    Label {
      anchors.fill: parent
      anchors.margins: 10 * Skin.u
      verticalAlignment: Text.AlignVCenter
      text: view.dragging ? view.dragging.title : ""
      font.pixelSize: 13 * Skin.u
    }
  }

  Label {
    anchors { bottom: parent.bottom; bottomMargin: 10 * Skin.u; horizontalCenter: parent.horizontalCenter }
    text: Skin.t("tasks.hint")
    color: Skin.dim
    font.pixelSize: 11 * Skin.u
  }
}

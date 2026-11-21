import QtQuick
import "kit"
import Quickshell
import Quickshell.Wayland
import "."

// One window as a card: its app's icon and title over a picture of it.
// The picture is a live capture of the window where Hyprland can give one,
// else the app's icon, large. Used by Alt+Tab, Task view and Snap assist.
Item {
  id: card

  property var win: null            // an entry from Desk.windowList
  property var toplevel: null       // its Wayland toplevel, for the capture
  property bool selected: false
  property bool live: false         // keep capturing, not one frame
  property bool closable: false
  property bool showTitle: true
  readonly property bool hovered: mouse.containsMouse

  signal clicked()
  signal closeRequested()
  signal pressed(real sceneX, real sceneY)
  signal moved(real sceneX, real sceneY)
  signal released(real sceneX, real sceneY)

  readonly property var entry: win ? DesktopEntries.heuristicLookup(win.appClass) : null
  readonly property string icon: {
    var name = entry && entry.icon ? String(entry.icon) : ""
    if (name === "") return ""
    if (name.charAt(0) === "/") return "file://" + name
    return Quickshell.iconPath(name, true) || ""
  }
  readonly property string appName: entry && entry.name ? String(entry.name) : (win ? win.appClass : "")

  Rectangle {
    id: frame
    anchors.fill: parent
    radius: 14 * Skin.u
    color: card.selected ? Skin.tint(Skin.accent, 0.16) : (card.hovered ? Skin.tint(Skin.fg, 0.07) : "transparent")
    border.width: card.selected ? 2 : (card.hovered ? 1 : 0)
    border.color: card.selected ? Skin.accent : Skin.tint(Skin.fg, 0.25)
    Behavior on color { ColorAnimation { duration: Skin.ms(120) } }
  }

  Row {
    id: titleRow
    visible: card.showTitle
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 * Skin.u }
    height: 22 * Skin.u
    spacing: 8 * Skin.u

    Image {
      width: 18 * Skin.u
      height: width
      anchors.verticalCenter: parent.verticalCenter
      source: card.icon
      sourceSize: Qt.size(width * 2, height * 2)
      visible: card.icon !== ""
      asynchronous: true
      smooth: true
    }
    Label {
      width: titleRow.width - (card.icon !== "" ? 26 * Skin.u : 0) - (closeButton.visible ? 30 * Skin.u : 0)
      anchors.verticalCenter: parent.verticalCenter
      text: card.win ? (card.win.title !== "" ? card.win.title : card.appName) : ""
      font.pixelSize: 13 * Skin.u
      font.weight: card.selected ? Font.DemiBold : Font.Normal
    }
  }

  Item {
    id: picture
    anchors {
      left: parent.left; right: parent.right; bottom: parent.bottom
      top: card.showTitle ? titleRow.bottom : parent.top
      margins: 10 * Skin.u
    }

    ScreencopyView {
      id: shot
      anchors.centerIn: parent
      width: implicitWidth > 0 ? implicitWidth : parent.width
      height: implicitHeight > 0 ? implicitHeight : parent.height
      constraintSize: Qt.size(picture.width, picture.height)
      captureSource: card.visible && card.toplevel ? card.toplevel : null
      live: card.live && card.visible
      paintCursor: false
      opacity: hasContent ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Skin.ms(140) } }
    }

    // No capture (yet): the app's icon on a faint plate.
    Rectangle {
      anchors.fill: parent
      visible: !shot.hasContent
      radius: 10 * Skin.u
      color: Skin.tint(Skin.fg, 0.05)
      border.width: 1
      border.color: Skin.tint(Skin.fg, 0.08)
      Image {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.42
        height: width
        source: card.icon
        sourceSize: Qt.size(width * 2, height * 2)
        visible: card.icon !== ""
        asynchronous: true
        smooth: true
      }
      Label {
        anchors.centerIn: parent
        visible: card.icon === ""
        text: card.appName.charAt(0).toUpperCase()
        color: Skin.dim
        font.pixelSize: Math.min(parent.width, parent.height) * 0.3
      }
    }

    // Minimized windows say so.
    Rectangle {
      visible: !!card.win && card.win.minimized
      anchors { left: parent.left; bottom: parent.bottom; margins: 6 * Skin.u }
      width: minLabel.implicitWidth + 14 * Skin.u
      height: 22 * Skin.u
      radius: height / 2
      color: Skin.tint(Skin.bg, 0.85)
      Label {
        id: minLabel
        anchors.centerIn: parent
        text: Skin.t("minimized")
        color: Skin.dim
        font.pixelSize: 11 * Skin.u
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    property bool dragging: false
    property point start
    onPressed: function(e) {
      dragging = false
      start = Qt.point(e.x, e.y)
      var p = mapToItem(null, e.x, e.y)
      card.pressed(p.x, p.y)
    }
    onPositionChanged: function(e) {
      if (!pressed) return
      if (Math.abs(e.x - start.x) + Math.abs(e.y - start.y) > 8) dragging = true
      var p = mapToItem(null, e.x, e.y)
      if (dragging) card.moved(p.x, p.y)
    }
    onReleased: function(e) {
      var p = mapToItem(null, e.x, e.y)
      if (dragging) card.released(p.x, p.y)
      else if (e.button === Qt.MiddleButton && card.closable) card.closeRequested()
      else if (e.button === Qt.LeftButton) card.clicked()
      dragging = false
    }
  }

  // Close, on hover, where closing is offered.
  Rectangle {
    id: closeButton
    visible: card.closable && (card.hovered || closeMouse.containsMouse)
    anchors { right: parent.right; top: parent.top; margins: 8 * Skin.u }
    width: 26 * Skin.u
    height: width
    radius: width / 2
    color: closeMouse.containsMouse ? Skin.urgent : Skin.tint(Skin.bg, 0.8)
    Label {
      anchors.centerIn: parent
      text: "✕"
      font.pixelSize: 12 * Skin.u
    }
    MouseArea {
      id: closeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: card.closeRequested()
    }
  }
}

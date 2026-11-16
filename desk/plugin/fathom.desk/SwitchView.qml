import QtQuick
import "."
import "Desk.js" as D

// Alt+Tab: every window as a card in one glass panel across the middle of
// the screen, most recently used first, the picked one outlined. Hyprland
// drives it (see Panel.qml); the arrow keys, Enter, Esc and the mouse work
// too once it shows.
Item {
  id: view

  property var windows: []
  property int selected: -1
  property var host: null

  signal picked(int index)
  signal moveRequested(int delta)
  signal cancelRequested()

  readonly property real cardW: 250 * Skin.u
  readonly property real cardH: cardW * 0.72
  readonly property real gap: 12 * Skin.u
  readonly property int perRow: Math.max(1, Math.floor((width * 0.9 - 40 * Skin.u + gap) / (cardW + gap)))
  readonly property int columns: Math.max(1, Math.min(windows.length, perRow))
  readonly property int rows: Math.max(1, Math.ceil(windows.length / perRow))
  readonly property int shownRows: Math.min(rows, Math.max(1, Math.floor((height * 0.8 - 80 * Skin.u) / (cardH + gap))))

  function key(e) {
    if (e.key === Qt.Key_Escape) { cancelRequested(); e.accepted = true }
    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { moveRequested(1); e.accepted = true }
    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) { moveRequested(-1); e.accepted = true }
    else if (e.key === Qt.Key_Down) { moveRequested(columns); e.accepted = true }
    else if (e.key === Qt.Key_Up) { moveRequested(-columns); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { picked(selected); e.accepted = true }
  }

  // A click outside the panel leaves things as they were.
  MouseArea {
    anchors.fill: parent
    onClicked: view.cancelRequested()
  }

  Glass {
    id: panel
    anchors.centerIn: parent
    width: Math.max(320 * Skin.u, view.columns * (view.cardW + view.gap) - view.gap + 40 * Skin.u)
    height: (view.windows.length === 0 ? 120 * Skin.u
      : view.shownRows * (view.cardH + view.gap) - view.gap + 40 * Skin.u)

    MouseArea { anchors.fill: parent }   // clicks on the panel stay on it

    Label {
      anchors.centerIn: parent
      visible: view.windows.length === 0
      text: Skin.t("switch.none")
      color: Skin.dim
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: 20 * Skin.u
      contentWidth: width
      contentHeight: grid.height
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      Grid {
        id: grid
        columns: view.columns
        spacing: view.gap

        Repeater {
          model: view.windows
          delegate: WindowCard {
            required property var modelData
            required property int index
            width: view.cardW
            height: view.cardH
            win: modelData
            toplevel: view.host ? view.host.toplevelFor(modelData.address) : null
            selected: index === view.selected
            live: selected
            onClicked: view.picked(index)
            onSelectedChanged: if (selected) {
              // Keep the picked card in sight when there are more rows than fit.
              var top = y, bottom = y + height
              if (top < flick.contentY) flick.contentY = top
              else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height
            }
          }
        }
      }
    }
  }

  // Under the panel: what the picked window is and where.
  Label {
    anchors { top: panel.bottom; topMargin: 12 * Skin.u; horizontalCenter: panel.horizontalCenter }
    width: Math.min(panel.width, view.width * 0.8)
    horizontalAlignment: Text.AlignHCenter
    visible: view.selected >= 0 && view.selected < view.windows.length
    readonly property var win: visible ? view.windows[view.selected] : null
    text: win ? (win.minimized ? Skin.t("switch.minimized") : Skin.t("switch.onWorkspace").arg(win.workspace)) : ""
    color: Skin.dim
    font.pixelSize: 12 * Skin.u
    style: Text.Outline
    styleColor: Skin.tint(Skin.bg, 0.6)
  }
}

import QtQuick
import QtQuick.Layouts
import "."

// A glass card with a title row, a scrolling body and an optional footer.
// Sized to its content; Layout.preferredWidth shares a row's width.
Rectangle {
  id: card
  property string title: ""
  property string subtitle: ""
  property color subtitleColor: Skin.dim
  property string glyph: ""
  default property alias content: body.data
  property alias footer: footerSlot.data

  Layout.fillWidth: true
  Layout.fillHeight: true
  Layout.preferredWidth: 1
  Layout.minimumHeight: 240 * Skin.u
  implicitHeight: inner.implicitHeight + 44 * Skin.u
  // Drawn as the Start menu's panel is (StartView.qml): 22 px corners (not
  // scaled; windows share them, theme/hyprland.lua), the
  // accent at 25% for the border, its glow along the top, and 90% over
  // Hyprland's blur. Without blur the deck's scrim is solid, and a card at
  // 62% on it keeps its shade apart from the scrim's.
  radius: 22
  color: Skin.tint(Skin.bg, Skin.glass ? 0.9 : 0.62)
  border.width: 1
  border.color: Skin.tint(Skin.accent, 0.25)

  // Swallow clicks so only the scrim around the cards closes the deck.
  MouseArea { anchors.fill: parent }

  // A faint top glow, like light catching glass.
  Rectangle {
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
    height: 90 * Skin.u
    radius: card.radius
    gradient: Gradient {
      GradientStop { position: 0; color: Skin.tint(Skin.accent, 0.09) }
      GradientStop { position: 1; color: "transparent" }
    }
  }

  ColumnLayout {
    id: inner
    anchors.fill: parent
    anchors.margins: 22 * Skin.u
    spacing: 14 * Skin.u

    RowLayout {
      Layout.fillWidth: true
      spacing: 10 * Skin.u
      Label {
        text: card.glyph
        color: Skin.accent
        font.pixelSize: 18 * Skin.u
        visible: card.glyph !== ""
      }
      Label {
        text: card.title
        font.pixelSize: 18 * Skin.u
        font.weight: Font.DemiBold
      }
      Item { Layout.fillWidth: true }
      Label {
        text: card.subtitle
        color: card.subtitleColor
        font.pixelSize: 12 * Skin.u
        horizontalAlignment: Text.AlignRight
        Layout.maximumWidth: card.width * 0.55
      }
    }

    Flickable {
      id: flick
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: body.implicitHeight
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ColumnLayout {
        id: body
        width: flick.width
        spacing: 12 * Skin.u
      }
    }

    RowLayout {
      id: footerSlot
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      visible: children.length > 0
    }
  }

  // A thin bar beside the body when it holds more than fits, so nothing
  // sits hidden below the card's edge without a hint.
  Rectangle {
    visible: flick.interactive
    x: card.width - 11 * Skin.u
    y: inner.y + flick.y + flick.visibleArea.yPosition * flick.height
    width: 3 * Skin.u
    height: flick.visibleArea.heightRatio * flick.height
    radius: width / 2
    color: Skin.tint(Skin.accent, 0.5)
  }
}

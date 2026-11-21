import QtQuick
import "kit"
import QtQuick.Layouts
import "."

// A glass card with a title row, a scrolling body and an optional footer.
// Sized to its content; Layout.preferredWidth shares a row's width.
Glass {
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
  // Fathom's panel (Glass.qml), but without blur the deck's scrim is solid,
  // and a card at 62% on it keeps its shade apart from the scrim's.
  alpha: Skin.glass ? Skin.glassAlpha : 0.62
  clip: false

  // Swallow clicks so only the scrim around the cards closes the deck.
  MouseArea { anchors.fill: parent }


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
        font.pixelSize: Skin.text.heading
        visible: card.glyph !== ""
      }
      Label {
        text: card.title
        font.pixelSize: Skin.text.heading
        font.weight: Font.DemiBold
      }
      Item { Layout.fillWidth: true }
      Label {
        text: card.subtitle
        color: card.subtitleColor
        font.pixelSize: Skin.text.detail
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

import QtQuick
import QtQuick.Layouts
import "."

// The Command Deck's content: a clock, page tabs, a summary line and the
// current page (Deck or Care) on a translucent scrim. Plain QtQuick only, so
// it can be rendered outside the shell for testing; Panel.qml supplies the
// data and sets the theme on Skin. Sits inside a Stage.
Item {
  id: deck

  // "deck" or "care".
  property string page: "deck"
  // Status JSON from `fathom-deck status` and `fathom-care status`.
  property var info: null
  property var care: null
  property string error: ""
  // Container names and Care items with an action in flight.
  property var busy: ({})
  property var cleaning: ({})
  property bool checking: false
  property bool shown: true

  signal closeRequested()
  signal pageRequested(string page)
  signal containerAction(string action, string name)
  signal logsRequested(string name)
  signal dockerRequested()
  signal cleanRequested(var ids, bool needsRoot)
  signal restartRequested(string scope, string unit)
  signal unitLogRequested(string scope, string unit)
  signal updateRequested()
  signal checkRequested()

  function switchPage() { pageRequested(page === "deck" ? "care" : "deck") }

  focus: true
  Keys.onEscapePressed: deck.closeRequested()
  Keys.onPressed: function(event) {
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
        || event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
      deck.switchPage()
      event.accepted = true
    }
  }

  // The scrim. Hyprland blurs what's behind it (see fathom-deck.lua).
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Skin.bg.r * 0.5, Skin.bg.g * 0.5, Skin.bg.b * 0.5, 0.62)
    MouseArea { anchors.fill: parent; onClicked: deck.closeRequested() }
  }

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: 48 * Skin.u
    opacity: deck.shown ? 1 : 0
    scale: deck.shown ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: 180 * Skin.motion; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 180 * Skin.motion; easing.type: Easing.OutCubic } }

    readonly property real contentWidth: Math.min(width, 1680 * Skin.u)

    ColumnLayout {
      id: column
      width: stage.contentWidth
      anchors.horizontalCenter: parent.horizontalCenter
      height: parent.height
      spacing: 28 * Skin.u
      // The height left for a page between the header and the footer.
      readonly property real pageRoom: Math.max(200 * Skin.u, height - header.height - footer.height - 3 * spacing)

      // Clock, tabs and summary.
      RowLayout {
        id: header
        Layout.fillWidth: true
        spacing: 32 * Skin.u

        ColumnLayout {
          spacing: 0
          Label {
            text: clock.now.toLocaleTimeString(Skin.locale, "HH:mm")
            font.pixelSize: 84 * Skin.u
            font.weight: Font.Light
            font.letterSpacing: -2 * Skin.u
          }
          Label {
            text: clock.now.toLocaleDateString(Skin.locale, "dddd d MMMM")
            color: Skin.dim
            font.pixelSize: 18 * Skin.u
          }
          Row {
            Layout.topMargin: 16 * Skin.u
            spacing: 8 * Skin.u
            Pill {
              text: Skin.t("tab.deck")
              glyph: ""
              selected: deck.page === "deck"
              onClicked: deck.pageRequested("deck")
            }
            Pill {
              readonly property int alerts: deck.care && Array.isArray(deck.care.warnings) ? deck.care.warnings.length : 0
              text: alerts > 0 ? Skin.t("tab.careCount").arg(Skin.n(alerts)) : Skin.t("tab.care")
              glyph: ""
              glyphColor: alerts > 0 ? Skin.warn : Skin.accent
              selected: deck.page === "care"
              onClicked: deck.pageRequested("care")
            }
          }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
          Layout.alignment: Qt.AlignBottom
          spacing: 8 * Skin.u
          Repeater {
            model: deck.page === "care" ? carePage.summary() : deckPage.summary()
            delegate: RowLayout {
              required property var modelData
              spacing: 10 * Skin.u
              Layout.alignment: Qt.AlignRight
              Dot { tone: Skin.levelColor(modelData.tone) }
              Label { text: modelData.text; font.pixelSize: 15 * Skin.u }
            }
          }
        }
      }

      DeckPage {
        id: deckPage
        visible: deck.page === "deck"
        Layout.fillWidth: true
        // As tall as the tallest card needs, shrinking (and scrolling) when
        // the screen is shorter. Nested layouts fill by default, hence the
        // explicit false.
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        columnCount: stage.contentWidth >= 1100 * Skin.u ? 4 : 2
        info: deck.info
        busy: deck.busy
        onContainerAction: function(action, name) { deck.containerAction(action, name) }
        onLogsRequested: function(name) { deck.logsRequested(name) }
        onDockerRequested: deck.dockerRequested()
      }

      CarePage {
        id: carePage
        visible: deck.page === "care"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        columns: stage.contentWidth >= 1100 * Skin.u ? 3 : 1
        care: deck.care
        checking: deck.checking
        cleaning: deck.cleaning
        onCleanRequested: function(ids, needsRoot) { deck.cleanRequested(ids, needsRoot) }
        onRestartRequested: function(scope, unit) { deck.restartRequested(scope, unit) }
        onLogRequested: function(scope, unit) { deck.unitLogRequested(scope, unit) }
        onUpdateRequested: deck.updateRequested()
        onCheckRequested: deck.checkRequested()
      }

      Item { Layout.fillHeight: true }

      // Footer.
      RowLayout {
        id: footer
        Layout.fillWidth: true
        Label {
          text: deck.error !== "" ? deck.error : Skin.t("hint")
          color: deck.error !== "" ? Skin.urgent : Skin.dim
          font.pixelSize: 12 * Skin.u
          Layout.fillWidth: true
        }
        Label {
          readonly property var source: deck.page === "care" ? deck.care : deck.info
          visible: !!source
          text: source ? Skin.t("updated").arg(new Date(source.time * 1000).toLocaleTimeString(Skin.locale, "HH:mm:ss")) : ""
          color: Skin.dim
          font.pixelSize: 12 * Skin.u
        }
      }
    }
  }

  QtObject {
    id: clock
    property date now: new Date()
  }
  Timer {
    interval: 1000
    running: deck.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: clock.now = new Date()
  }
}

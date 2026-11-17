import QtQuick
import QtQuick.Layouts
import "."

// The Command Deck's content: a clock, page tabs, a summary line and the
// current page (Deck or Care) on a translucent scrim. Plain QtQuick only, so
// it can be rendered outside the shell for testing; Panel.qml supplies the
// data and sets the theme on Skin. Sits inside a Stage.
Item {
  id: deck

  // "deck", "care", "sentinel", "pulse", "crumbs" or "look" (Personalise).
  property string page: "deck"
  // Status JSON from `fathom-deck status` and `fathom-care status`.
  property var info: null
  property var care: null
  property var sentinel: null
  property var pulse: null
  property string pulseRange: "15m"
  // `fathom-pulse agents`: Claude Code's day, for the Pulse page.
  property var agents: null
  // `fathom-look state`, whether a change is being applied, and how the
  // last one went.
  property var look: null
  property bool lookBusy: false
  property string lookMessage: ""
  property bool lookFailed: false
  // `fathom-crumbs status`, the chosen domain and its cookies.
  property var crumbs: null
  property var crumbsDetail: null
  property string crumbsSelected: ""
  property bool crumbsBusy: false
  property string crumbsMessage: ""
  property bool crumbsFailed: false
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
  signal lockdownRequested(bool on)
  signal blockRequested(string ip)
  signal unblockRequested(string ip)
  signal trustRequested(string mac, bool trust)
  signal checkFilesRequested()
  signal sentinelLogRequested(string what)
  signal snitchRequested()
  signal pulseRangeRequested(string range)
  signal askRequested(string text)
  signal lookApplyRequested(var args)
  signal lookBarRequested(string mode)
  signal lookWallpaperRequested(string path)
  signal crumbsSelectRequested(string domain)
  signal crumbsApplyRequested(var args)
  signal crumbsClearRequested()
  signal crumbsForgetRequested(string domain, string browser)

  readonly property var pages: ["deck", "care", "sentinel", "pulse", "crumbs", "look"]
  function switchPage(step) {
    var i = pages.indexOf(page)
    pageRequested(pages[(i + (step || 1) + pages.length) % pages.length])
  }

  focus: true
  Keys.onEscapePressed: deck.closeRequested()
  Keys.onPressed: function(event) {
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown)) {
      deck.switchPage(1)
      event.accepted = true
    } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp)) {
      deck.switchPage(-1)
      event.accepted = true
    }
  }

  // The scrim. Hyprland blurs what's behind it (see fathom-deck.lua) when
  // blur is on; without blur it is solid, so text behind can't show (at 94%
  // it still read faintly: brightest 0.085 grayscale).
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Skin.bg.r * 0.5, Skin.bg.g * 0.5, Skin.bg.b * 0.5, Skin.glass ? 0.62 : 1)
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
            Pill {
              readonly property int alerts: deck.sentinel ? deck.sentinel.attention || 0 : 0
              text: alerts > 0 ? Skin.t("tab.sentinelCount").arg(Skin.n(alerts)) : Skin.t("tab.sentinel")
              glyph: "\uf132"
              glyphColor: alerts > 0 ? Skin.warn : Skin.accent
              selected: deck.page === "sentinel"
              onClicked: deck.pageRequested("sentinel")
            }
            Pill {
              text: Skin.t("tab.pulse")
              glyph: "\uf0e7"
              selected: deck.page === "pulse"
              onClicked: deck.pageRequested("pulse")
            }
            Pill {
              text: Skin.t("tab.crumbs")
              glyph: "\uf1e0"
              selected: deck.page === "crumbs"
              onClicked: deck.pageRequested("crumbs")
            }
            Pill {
              text: Skin.t("tab.look")
              glyph: "\uf1fc"
              selected: deck.page === "look"
              onClicked: deck.pageRequested("look")
            }
          }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
          Layout.alignment: Qt.AlignBottom
          spacing: 8 * Skin.u
          Repeater {
            model: deck.page === "care" ? carePage.summary()
              : (deck.page === "sentinel" ? sentinelPage.summary()
              : (deck.page === "pulse" ? pulsePage.summary()
              : (deck.page === "look" ? lookPage.summary()
              : (deck.page === "crumbs" ? crumbsPage.summary() : deckPage.summary()))))
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

      SentinelPage {
        id: sentinelPage
        visible: deck.page === "sentinel"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        columns: stage.contentWidth >= 1100 * Skin.u ? 3 : 1
        sentinel: deck.sentinel
        onLockdownRequested: function(on) { deck.lockdownRequested(on) }
        onBlockRequested: function(ip) { deck.blockRequested(ip) }
        onUnblockRequested: function(ip) { deck.unblockRequested(ip) }
        onTrustRequested: function(mac, trust) { deck.trustRequested(mac, trust) }
        onCheckFilesRequested: deck.checkFilesRequested()
        onLogRequested: function(what) { deck.sentinelLogRequested(what) }
        onSnitchRequested: deck.snitchRequested()
      }

      PulsePage {
        id: pulsePage
        visible: deck.page === "pulse"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        wide: stage.contentWidth >= 1100 * Skin.u
        pulse: deck.pulse
        agents: deck.agents
        range: deck.pulseRange
        onRangeRequested: function(range) { deck.pulseRangeRequested(range) }
        onAskRequested: function(text) { deck.askRequested(text) }
      }

      CrumbsPage {
        id: crumbsPage
        visible: deck.page === "crumbs"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        wide: stage.contentWidth >= 1100 * Skin.u
        crumbs: deck.crumbs
        detail: deck.crumbsDetail
        selected: deck.crumbsSelected
        busy: deck.crumbsBusy
        message: deck.crumbsMessage
        failed: deck.crumbsFailed
        onSelectRequested: function(domain) { deck.crumbsSelectRequested(domain) }
        onApplyRequested: function(args) { deck.crumbsApplyRequested(args) }
        onClearRequested: deck.crumbsClearRequested()
        onForgetRequested: function(domain, browser) { deck.crumbsForgetRequested(domain, browser) }
      }

      LookPage {
        id: lookPage
        visible: deck.page === "look"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: column.pageRoom
        columns: stage.contentWidth >= 1100 * Skin.u ? 3 : 1
        lookState: deck.look
        busy: deck.lookBusy
        message: deck.lookMessage
        failed: deck.lookFailed
        onApplyRequested: function(args) { deck.lookApplyRequested(args) }
        onBarRequested: function(mode) { deck.lookBarRequested(mode) }
        onWallpaperRequested: function(path) { deck.lookWallpaperRequested(path) }
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
          readonly property var source: deck.page === "care" ? deck.care : (deck.page === "sentinel" ? deck.sentinel
            : (deck.page === "pulse" ? deck.pulse : (deck.page === "crumbs" ? deck.crumbs
            : (deck.page === "look" ? null : deck.info))))
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

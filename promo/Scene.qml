import QtQuick
import QtQuick.Window
import "../deck/plugin/fathom.deck"
import "../deck/plugin/fathom.deck/kit"

// Renders one of the Command Deck's pages, or Start, outside the shell from
// demo-data.py's output, and saves it as a PNG:
//   qml6 Scene.qml -- <data dir> <page> <font family> <out.png> [scale]
// page: deck, care, sentinel, pulse, crumbs or start. The window is a
// 1920 x 1080 screen; scale is the deck's own (Skin.u), 1.2 by default, so
// the page fills the frame as it would a 1080p screen at that scale.
Window {
  id: win
  width: 1920
  height: 1080
  visible: true
  color: "#04070f"

  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property string dataDir: args[0]
  readonly property string page: args[1]
  readonly property string out: args[3]
  readonly property real scale: args.length > 4 ? Number(args[4]) : 1.2

  function read(name) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + (name.charAt(0) === "/" ? name : dataDir + "/" + name), false)
    xhr.send()
    return JSON.parse(xhr.responseText)
  }

  // The deck's strings, as the shell's Translations would give them.
  readonly property var catalog: read(Qt.resolvedUrl("../deck/plugin/fathom.deck/i18n/en.json").toString().replace("file://", ""))
  readonly property var strings: ({
    t: function(key) { var v = win.catalog[key]; return typeof v === "string" ? v : key },
    tn: function(key, n) {
      var v = win.catalog[key]
      if (v && typeof v === "object") return n === 1 ? v.one : v.other
      return typeof v === "string" ? v : key
    }
  })

  // Start opens over the desktop: Fathom's own wallpaper.
  Image {
    anchors.fill: parent
    visible: win.page === "start"
    source: Qt.resolvedUrl("../theme/backgrounds/1-horizon.webp")
    fillMode: Image.PreserveAspectCrop
  }

  Item { id: overlay; anchors.fill: parent; z: 10 }

  Loader {
    anchors.fill: parent
    sourceComponent: win.page === "start" ? startScene : deckScene
  }

  Component {
    id: deckScene
    DeckView {
      id: deckView
      // As the shell does: open on the Deck page, then switch. A page laid
      // out while hidden from the start keeps a narrow width.
      page: "deck"
      shown: true
      Timer { interval: 300; running: true; onTriggered: deckView.page = win.page === "care" ? "sentinel" : win.page }
      Timer { interval: 700; running: true; onTriggered: deckView.page = win.page }
      info: win.page === "deck" ? win.read("deck.json") : null
      care: win.read("care.json")
      sentinel: win.read("sentinel.json")
      pulse: win.page === "pulse" ? win.read("pulse.json") : null
      agents: win.page === "pulse" ? win.read("agents.json") : null
      crumbs: win.read("crumbs-status.json")
      crumbsDetail: win.page === "crumbs" ? win.read("crumbs-detail.json") : null
      crumbsSelected: win.page === "crumbs" ? "doubleclick.net" : ""
    }
  }

  Component {
    id: startScene
    StartView {
      shown: true
      apps: win.read("apps.json")
      menu: win.read("start.json")
    }
  }

  Component.onCompleted: {
    Skin.strings = strings
    Skin.fontFamily = args[2]
    Skin.overlay = overlay
    Skin.u = win.scale
  }

  Timer {
    interval: 1500
    running: true
    onTriggered: win.contentItem.grabToImage(function(result) {
      result.saveToFile(win.out)
      Qt.quit()
    })
  }
}

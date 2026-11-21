import QtQuick
import QtQuick.Window
import "../../deck/plugin/fathom.deck"
import "../../deck/plugin/fathom.deck/kit"

// Renders the Command Deck's Crumbs page outside the shell, from
// make-demo.py's output, and saves it. make-preview.sh runs it:
//   qml6 Preview.qml -- <demo dir> <font family> <out.png>
Window {
  id: win
  width: 2000
  height: 1250
  visible: true
  color: "#04070f"

  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property string demoDir: args[0]
  readonly property string out: args[2]

  function read(path) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + path, false)
    xhr.send()
    return JSON.parse(xhr.responseText)
  }

  // The deck's strings, as the shell's Translations would give them.
  readonly property var catalog: read(Qt.resolvedUrl("../../deck/plugin/fathom.deck/i18n/en.json").toString().replace("file://", ""))
  readonly property var strings: ({
    t: function(key) { var v = win.catalog[key]; return typeof v === "string" ? v : key },
    tn: function(key, n) {
      var v = win.catalog[key]
      if (v && typeof v === "object") return n === 1 ? v.one : v.other
      return typeof v === "string" ? v : key
    }
  })

  Item {
    id: overlay
    anchors.fill: parent
    z: 10
  }

  DeckView {
    id: deck
    anchors.fill: parent
    page: "crumbs"
    shown: true
    crumbs: win.read(win.demoDir + "/status.json")
    crumbsDetail: win.read(win.demoDir + "/detail.json")
    crumbsSelected: "doubleclick.net"
  }

  Component.onCompleted: {
    Skin.strings = strings
    Skin.fontFamily = args[1]
    Skin.overlay = overlay
    Skin.u = 1
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

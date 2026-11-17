import QtQuick
import QtQuick.Window

// The promo's title and end cards, 1920 x 1080:
//   qml6 Card.qml -- title|end <font family> <out.png>
Window {
  id: win
  width: 1920
  height: 1080
  visible: true
  color: "#04070f"

  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property string kind: args[0]
  readonly property string font: args[1]
  readonly property color fg: "#e6f0ff"
  readonly property color dim: "#8fa3bf"
  readonly property color cyan: "#4cc9f0"
  readonly property color violet: "#9d8cff"

  Image {
    anchors.fill: parent
    source: Qt.resolvedUrl(win.kind === "title" ? "../theme/backgrounds/1-horizon.webp" : "../theme/backgrounds/3-hexgrid.webp")
    fillMode: Image.PreserveAspectCrop
    opacity: win.kind === "title" ? 1 : 0.8
  }

  Column {
    visible: win.kind === "title"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 300
    spacing: 22
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Fathom"
      color: win.fg
      font.family: win.font
      font.pixelSize: 150
      font.weight: Font.Light
      font.letterSpacing: -4
    }
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 420
      height: 3
      radius: 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: win.cyan }
        GradientStop { position: 1; color: win.violet }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "A futuristic, Windows-inspired desktop layer for Omarchy"
      color: win.fg
      font.family: win.font
      font.pixelSize: 34
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Built for Docker, .NET and AI work"
      color: win.dim
      font.family: win.font
      font.pixelSize: 26
    }
  }

  Column {
    visible: win.kind === "end"
    anchors.centerIn: parent
    spacing: 18
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Fathom"
      color: win.fg
      font.family: win.font
      font.pixelSize: 110
      font.weight: Font.Light
      font.letterSpacing: -3
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "github.com/nerdcules/fathom  ·  MIT licence"
      color: win.cyan
      font.family: win.font
      font.pixelSize: 34
    }
    Item { width: 1; height: 26 }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Idea: nerdcules  ·  Written by Claude, in Claude Code"
      color: win.fg
      font.family: win.font
      font.pixelSize: 30
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "31 of 31 commits co-authored by Claude (3d2e74a, 17 Nov 2026)"
      color: win.dim
      font.family: win.font
      font.pixelSize: 22
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Tests at 3d2e74a: 129 Python and 58 Node, all passing"
      color: win.dim
      font.family: win.font
      font.pixelSize: 22
    }
    Item { width: 1; height: 20 }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "The Start, Deck, Care, Sentinel, Pulse and Crumbs scenes show made-up demo data"
      color: win.dim
      font.family: win.font
      font.pixelSize: 20
      font.italic: true
    }
  }

  Timer {
    interval: 1200
    running: true
    onTriggered: win.contentItem.grabToImage(function(result) {
      result.saveToFile(win.args[2])
      Qt.quit()
    })
  }
}

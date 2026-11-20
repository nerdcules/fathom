import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "."

// Gives a dropdown's DropSkin the theme, as the desk's Panel.qml does for
// Quick settings: Omarchy's colours, font, corners and menu alphas, the
// plugin's strings, whether Hyprland blurs (glass, else solid) and the
// glow from Personalise (look.json). One per dropdown, inside its card, so
// it runs when the dropdown first opens.
Item {
  id: theme
  visible: false
  property var strings: null

  Binding { target: DropSkin; property: "fg"; value: Commons.Color.foreground }
  Binding { target: DropSkin; property: "bg"; value: Commons.Color.background }
  Binding { target: DropSkin; property: "accent"; value: Commons.Color.accent }
  Binding { target: DropSkin; property: "urgent"; value: Commons.Color.urgent }
  Binding { target: DropSkin; property: "fontFamily"; value: Style.font.family }
  Binding { target: DropSkin; property: "motion"; value: Style.duration(100) / 100 }
  Binding { target: DropSkin; property: "radius"; value: Style.cornerRadius }
  Binding { target: DropSkin; property: "glassAlpha"; value: Commons.Color.menu.background.a }
  Binding { target: DropSkin; property: "edgeAlpha"; value: Commons.Color.menu.border.a }
  Binding { target: DropSkin; property: "strings"; value: theme.strings; when: theme.strings !== null }

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/fathom/look.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var look = JSON.parse(text())
        DropSkin.glow = look.glow !== false
      } catch (e) { DropSkin.glow = true }
    }
    onLoadFailed: DropSkin.glow = true
  }

  Process {
    running: true
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var o = JSON.parse(text)
          DropSkin.glass = o.bool !== undefined ? !!o.bool : !!o.int
        } catch (e) {}
      }
    }
  }
}

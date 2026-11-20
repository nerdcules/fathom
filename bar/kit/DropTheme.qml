import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "."

// Gives a dropdown's DropSkin the theme, as the desk's Panel.qml does for
// Quick settings: Omarchy's colours, font, corners and menu alphas, the
// plugin's strings, Fathom's size for the screen, whether Hyprland blurs
// (glass, else solid) and the glow from Personalise (look.json). One per
// dropdown, made with its button so the size is right on the first open;
// `screen` is the screen it opens on (its popup frame's).
Item {
  id: theme
  visible: false
  property var strings: null
  property var screen: null

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
  // Fathom's size for the screen, the rule the deck's Stage.qml and the
  // desk's Panel.qml use.
  Binding {
    target: DropSkin
    property: "u"
    when: !!theme.screen && theme.screen.width > 0 && theme.screen.height > 0
    value: Math.max(0.7, Math.min(1.25, Math.min(theme.screen.width / 1600, theme.screen.height / 1000)))
  }

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

import QtQuick
import "."

// The desk's panels, drawn as the Start menu's is (deck/plugin/fathom.deck/
// StartView.qml): the theme's background at 90% over Hyprland's blur (solid
// without blur), a 1 px border of the accent at 25%, 22 px corners, and the
// accent's glow along the top edge.
Rectangle {
  id: glass
  radius: 22 * Skin.u
  color: Skin.tint(Skin.bg, Skin.panelAlpha)
  border.width: 1
  border.color: Skin.tint(Skin.accent, 0.25)
  clip: true

  Rectangle {
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
    height: Math.min(90 * Skin.u, glass.height - 2)
    radius: glass.radius
    gradient: Gradient {
      GradientStop { position: 0; color: Skin.tint(Skin.accent, 0.09) }
      GradientStop { position: 1; color: "transparent" }
    }
  }
}

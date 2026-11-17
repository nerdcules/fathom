import QtQuick
import "."

// The desk's panels, drawn as the Start menu's is (deck/plugin/fathom.deck/
// StartView.qml): the theme's background at the look's opacity over
// Hyprland's blur (solid without blur), a 1 px border of the accent, the
// windows' corners (not scaled), and the accent's glow along the top edge.
// Skin.qml says where each comes from.
Rectangle {
  id: glass
  radius: Skin.radius
  color: Skin.tint(Skin.bg, Skin.panelAlpha)
  border.width: 1
  border.color: Skin.tint(Skin.accent, Skin.edgeAlpha)
  clip: true

  Rectangle {
    visible: Skin.glow
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
    height: Math.min(90 * Skin.u, glass.height - 2)
    radius: glass.radius
    gradient: Gradient {
      GradientStop { position: 0; color: Skin.tint(Skin.accent, 0.09) }
      GradientStop { position: 1; color: "transparent" }
    }
  }
}

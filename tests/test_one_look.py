"""Fathom looks the same everywhere (the user's rule, #14).

The look lives in three copies, one per shell plugin, because a plugin can
only load its own files: the Command Deck's Skin.qml, the desk's Skin.qml
(Quick settings, Alt+Tab, Task view, Snap) and the bar dropdowns' kit
DropSkin.qml. These tests fail when the copies drift apart: the shared
values and formulas, what each takes from the theme, and the size rule for
the screen.
"""

import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKINS = {
    "deck": "deck/plugin/fathom.deck/Skin.qml",
    "desk": "desk/plugin/fathom.desk/Skin.qml",
    "bar": "bar/kit/DropSkin.qml",
}
# Where each sets its skin from the theme, and the name of its skin there.
THEMES = {
    "deck": ("deck/plugin/fathom.deck/Panel.qml", "Skin"),
    "desk": ("desk/plugin/fathom.desk/Panel.qml", "Skin"),
    "bar": ("bar/kit/DropTheme.qml", "DropSkin"),
}
SIZES = {
    "deck": "deck/plugin/fathom.deck/Stage.qml",
    "desk": "desk/plugin/fathom.desk/Panel.qml",
    "bar": "bar/kit/DropTheme.qml",
}

# The look every copy has: colours, font, motion, size, glass, corners,
# opacity, edge, glow, and the derived tints.
SHARED = ["fg", "bg", "accent", "urgent", "ok", "warn", "violet", "fontFamily", "motion", "u", "glass",
          "radius", "glassAlpha", "edgeAlpha", "glow", "dim", "faint", "panelAlpha", "tint", "t", "tn"]
# What every copy takes from Omarchy's theme.
FROM_THEME = ["fg", "bg", "accent", "urgent", "fontFamily", "motion", "radius", "glassAlpha", "edgeAlpha"]


def read(path):
    with open(os.path.join(REPO, path)) as f:
        return f.read()


def skin(path):
    """Each property's and function's definition, by name, without the
    skin's own name in it."""
    out = {}
    for line in read(path).splitlines():
        m = re.match(r"\s*(?:readonly\s+)?property\s+\w+\s+(\w+)\s*:\s*(.+?)\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
            continue
        m = re.match(r"\s*function\s+(\w+)\s*(\(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def theme_bindings(path, name):
    found = {}
    for m in re.finditer(r"Binding\s*\{\s*target:\s*" + name + r";\s*property:\s*\"(\w+)\";\s*value:\s*([^;}]+?)\s*[;}]",
                         read(path)):
        found[m.group(1)] = m.group(2)
    return found


class OneLook(unittest.TestCase):
    def test_the_three_copies_share_the_look(self):
        skins = {k: skin(p) for k, p in SKINS.items()}
        for name in SHARED:
            values = {k: s.get(name) for k, s in skins.items()}
            self.assertNotIn(None, values.values(), f"{name} is in every copy: {values}")
            self.assertEqual(len(set(values.values())), 1, f"{name} is the same in every copy: {values}")

    def test_each_takes_the_same_from_the_theme(self):
        bindings = {k: theme_bindings(p, n) for k, (p, n) in THEMES.items()}
        for name in FROM_THEME:
            values = {k: b.get(name) for k, b in bindings.items()}
            self.assertNotIn(None, values.values(), f"{name} comes from the theme in every copy: {values}")
            self.assertEqual(len(set(values.values())), 1, f"{name} comes from the same place: {values}")

    def test_each_sizes_for_the_screen_by_the_same_rule(self):
        rule = re.compile(r"Math\.max\(0\.7, Math\.min\(1\.25, Math\.min\([^/]+/ 1600, [^/]+/ 1000\)\)\)")
        for k, path in SIZES.items():
            self.assertRegex(read(path), rule, f"{k}: clamp(0.7, 1.25, min(width/1600, height/1000))")

    def test_the_dropdowns_draw_the_glass_as_the_desk_does(self):
        # Quick settings' panel (desk Glass.qml) and a dropdown's card.
        glass = read("desk/plugin/fathom.desk/Glass.qml").replace("Skin.", "S.")
        card = read("bar/kit/DropCard.qml").replace("DropSkin.", "S.")
        for line in ("radius: S.radius", "color: S.tint(S.bg, S.panelAlpha)", "border.width: 1",
                     "border.color: S.tint(S.accent, S.edgeAlpha)", "visible: S.glow",
                     "GradientStop { position: 0; color: S.tint(S.accent, 0.09) }"):
            self.assertIn(line, glass)
            self.assertIn(line, card)


if __name__ == "__main__":
    unittest.main()

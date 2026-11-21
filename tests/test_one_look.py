"""Fathom looks the same everywhere (the user's rule, #14), from one kit (#22).

The look and the parts every surface shares (Skin, Label, Pill, Glass, Tip,
Dot and the bar dropdowns' parts) live once, in kit/. Each shell plugin that
draws with them (the Command Deck, the desk, each bar dropdown) has kit/ as
a link to it in the repo, and install.sh gives the installed plugin a copy:
a plugin can only load its own files. These tests fail when a plugin grows
its own copy again, uses something the skin doesn't have, or takes the
theme or sizes for the screen differently.
"""

import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(REPO, "kit")

# The plugins drawn with the kit.
PLUGINS = ["deck/plugin/fathom.deck", "desk/plugin/fathom.desk"] + sorted(
    os.path.join("bar/plugin", p) for p in os.listdir(os.path.join(REPO, "bar/plugin")))
# Where each binds the theme into the skin, and its size rule.
THEMES = ["deck/plugin/fathom.deck/Panel.qml", "desk/plugin/fathom.desk/Panel.qml", "kit/DropTheme.qml"]
SIZES = ["deck/plugin/fathom.deck/Stage.qml", "desk/plugin/fathom.desk/Panel.qml", "kit/DropTheme.qml"]
# What every surface takes from Omarchy's theme.
FROM_THEME = ["fg", "bg", "accent", "urgent", "fontFamily", "motion", "radius", "glassAlpha", "edgeAlpha"]


def read(path):
    with open(os.path.join(REPO, path)) as f:
        return f.read()


def qml_files(folder):
    """Fathom's own QML and JS in a folder; not the files a dropdown copies
    unchanged from Omarchy (they say so on their first line), which keep
    Omarchy's look and are checked against Omarchy instead (test_bar)."""
    for name in sorted(os.listdir(os.path.join(REPO, folder))):
        if name.endswith(".qml") or name.endswith(".js"):
            path = os.path.join(folder, name)
            with open(os.path.join(REPO, path)) as f:
                if f.readline().startswith("// Copied unchanged from Omarchy"):
                    continue
            yield path


def skin_members():
    out = set()
    for line in read("kit/Skin.qml").splitlines():
        m = re.match(r"\s*(?:readonly\s+)?property\s+[\w.]+\s+(\w+)\s*:", line) or re.match(r"\s*function\s+(\w+)\s*\(", line)
        if m:
            out.add(m.group(1))
    return out


def theme_bindings(path):
    found = {}
    for m in re.finditer(r"Binding\s*\{\s*target:\s*Skin;\s*property:\s*\"(\w+)\";\s*value:\s*([^;}]+?)\s*[;}]", read(path)):
        found[m.group(1)] = m.group(2)
    return found


class OneKit(unittest.TestCase):
    def test_each_plugins_kit_is_the_repos(self):
        for plugin in PLUGINS:
            link = os.path.join(REPO, plugin, "kit")
            self.assertTrue(os.path.islink(link), f"{plugin}/kit is a link to kit/")
            self.assertEqual(os.readlink(link), "../../../kit", plugin)
            self.assertEqual(os.path.realpath(link), os.path.realpath(KIT), plugin)

    def test_no_plugin_has_its_own_copy_of_a_kit_part(self):
        parts = {n for n in os.listdir(KIT) if n.endswith(".qml") or n.endswith(".js")}
        # And the names the copies had before #22.
        parts |= {"DropSkin.qml", "DropLabel.qml", "DropButton.qml", "Button.qml"}
        for plugin in PLUGINS:
            own = parts & set(os.listdir(os.path.join(REPO, plugin)))
            self.assertEqual(own, set(), f"{plugin} draws with kit/, not its own copies")

    def test_every_qml_file_in_a_plugin_imports_the_kit(self):
        for plugin in PLUGINS:
            for path in qml_files(plugin):
                if path.endswith(".qml") and re.search(r"\b(Skin|Label|Pill|Glass|Tip|Dot)\b", read(path)):
                    self.assertRegex(read(path), r'(?m)^import "kit"$', path)

    def test_the_skin_has_everything_the_parts_ask_of_it(self):
        members = skin_members()
        for folder in ["kit"] + PLUGINS:
            for path in qml_files(folder):
                code = re.sub(r"//[^\n]*", "", read(path))   # not the comments
                for name in set(re.findall(r"\bSkin\.(\w+)", code)):
                    self.assertIn(name, members, f"{path}: Skin.{name}")

    def test_each_takes_the_same_from_the_theme(self):
        bindings = {p: theme_bindings(p) for p in THEMES}
        for name in FROM_THEME:
            values = {p: b.get(name) for p, b in bindings.items()}
            self.assertNotIn(None, values.values(), f"{name} comes from the theme everywhere: {values}")
            self.assertEqual(len(set(values.values())), 1, f"{name} comes from the same place: {values}")

    def test_each_sizes_for_the_screen_by_the_same_rule(self):
        rule = re.compile(r"Math\.max\(0\.7, Math\.min\(1\.25, Math\.min\([^/]+/ 1600, [^/]+/ 1000\)\)\)")
        for path in SIZES:
            self.assertRegex(read(path), rule, f"{path}: clamp(0.7, 1.25, min(width/1600, height/1000))")

    def test_panels_are_drawn_by_glass(self):
        # The panel's edge and glow are drawn in one place; the Start menu,
        # the deck's cards and the dropdowns' card use it.
        edge = "border.color: Skin.tint(Skin.accent, Skin.edgeAlpha)"
        glow = "GradientStop { position: 0; color: Skin.tint(Skin.accent, 0.09) }"
        for folder in ["kit"] + PLUGINS:
            for path in qml_files(folder):
                if path == "kit/Glass.qml":
                    continue
                self.assertNotIn(edge, read(path), path)
                self.assertNotIn(glow, read(path), path)
        for path in ("deck/plugin/fathom.deck/StartView.qml", "deck/plugin/fathom.deck/Card.qml", "kit/DropCard.qml"):
            self.assertRegex(read(path), r"\bGlass \{", path)

    def test_one_ladder_of_states(self):
        # #18: hover, pressed and selected come from the skin, at the
        # strengths Omarchy's controls take from the theme.
        theme = read("theme/shell.toml")
        skin = read("kit/Skin.qml")
        for token, prop in (("hover-cursor-fill-alpha", "hoverFill"), ("pressed-fill-alpha", "pressedFill"),
                            ("selected-fill-alpha", "selectedFill"), ("selected-border-alpha", "selectedEdge")):
            value = re.search(r"(?m)^" + token + r"\s*=\s*([0-9.]+)", theme).group(1)
            self.assertRegex(skin, r"property color " + prop + r": tint\(accent, " + re.escape(value) + r"\)", prop)
        for path in ("kit/Pill.qml", "kit/DropRow.qml", "desk/plugin/fathom.desk/QuickTile.qml",
                     "desk/plugin/fathom.desk/QuickList.qml", "deck/plugin/fathom.deck/ListRow.qml"):
            src = read(path)
            self.assertRegex(src, r"Skin\.(stateFill\(|selectedFill)", path)
            own = re.findall(r"Skin\.tint\(Skin\.(?:fg|accent), 0\.(?:1[1-6]|22|36|45|8)\)", src)
            self.assertEqual(own, [], f"{path}: states come from the skin")

    def test_idle_controls_have_an_edge_you_can_see(self):
        # #21: 0.4 of the foreground on the panel is 3.47:1, over 3:1.
        theme = re.search(r"(?m)^normal-border-alpha\s*=\s*([0-9.]+)", read("theme/shell.toml")).group(1)
        self.assertEqual(theme, "0.4")
        self.assertIn("readonly property color idleEdge: tint(fg, " + theme + ")", read("kit/Skin.qml"))
        self.assertIn("Skin.idleEdge", read("kit/Pill.qml"))
        for path in ("kit/DropSearch.qml", "kit/DropFields.qml", "desk/plugin/fathom.desk/QuickList.qml"):
            self.assertIn("Skin.idleEdge", read(path), f"{path}: a text field's edge")

    def test_focus_is_a_ring_of_its_own(self):
        # #16: focus is FocusRing (foreground, outside the part), never the
        # selected look; only a text field shows focus with its edge.
        fields = ("password", "field", "input", "hexField", "search")
        for folder in ["kit"] + PLUGINS:
            for path in qml_files(folder):
                for line in read(path).splitlines():
                    if re.search(r"\b(border\.width|border\.color|color):.*\bactiveFocus\b", line):
                        self.assertTrue(any(f + ".activeFocus" in line for f in fields), f"{path}: {line.strip()}")
        for path in ("kit/Pill.qml", "kit/DropRow.qml", "kit/DropSlider.qml", "desk/plugin/fathom.desk/QuickTile.qml",
                     "desk/plugin/fathom.desk/SliderRow.qml", "deck/plugin/fathom.deck/StartView.qml",
                     "deck/plugin/fathom.deck/LookPage.qml"):
            self.assertIn("FocusRing {", read(path), path)
        ring = read("kit/FocusRing.qml")
        self.assertIn("border.color: Skin.fg", ring)
        self.assertIn("border.width: 2", ring)
        self.assertRegex(read("theme/shell.toml"), r'(?m)^focus-color\s*=\s*"foreground"')

    def test_inner_corners_follow_personalise(self):
        # #19: an inner corner is Skin.corner(n), n at Fathom's own 22,
        # scaled with Personalise's corners; round things stay round.
        self.assertIn("function corner(n) { return Math.round(n * u * radius / 22) }", read("kit/Skin.qml"))
        for folder in ["kit"] + PLUGINS:
            for path in qml_files(folder):
                fixed = re.findall(r"radius: \d+ \* Skin\.u", read(path))
                self.assertEqual(fixed, [], f"{path}: a corner from Skin.corner()")

    def test_font_sizes_are_named(self):
        # #20: every size comes from Skin.text, Fathom's named scale.
        scale = re.search(r"readonly property var text: \(\{(.*?)\}\)", read("kit/Skin.qml"), re.S).group(1)
        names = dict(re.findall(r"(\w+): (\d+) \* u", scale))
        self.assertEqual(names, {"caption": "11", "detail": "12", "body": "13", "label": "14", "title": "15",
                                 "large": "17", "heading": "18", "greeting": "26", "display": "30", "clock": "84"})
        for folder in ["kit"] + PLUGINS:
            for path in qml_files(folder):
                src = read(path)
                self.assertEqual(re.findall(r"pixelSize: \d[^\n]*", src), [], f"{path}: a size from Skin.text")
                for name in re.findall(r"Skin\.text\.(\w+)", src):
                    self.assertIn(name, names, f"{path}: Skin.text.{name}")


if __name__ == "__main__":
    unittest.main()

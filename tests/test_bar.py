"""Fathom's bar dropdowns (#14): each Omarchy bar item gets a Fathom one.

Each dropdown is drawn by the kit's factory from a description its plugin
gives (bar/README.md). The QML test runs the factory offscreen with the kit
beside it as kit/, as install.sh puts it; tests/bar.test.mjs checks each
plugin's description.
"""

import glob
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from test_start_clicks import qmltestrunner

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAR = os.path.join(REPO, "bar")


class Factory(unittest.TestCase):
    """The kit draws a dropdown from a description (kit/DropSections.qml)."""

    def test_sections_with_clicks_and_keys(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        shutil.copytree(os.path.join(BAR, "kit"), os.path.join(tmp, "kit"))
        shutil.copy(os.path.join(REPO, "tests", "qml", "bar", "tst_drop_sections.qml"), tmp)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        r = subprocess.run([qmltestrunner(), "-input", os.path.join(tmp, "tst_drop_sections.qml")],
                           env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])
        self.assertIn(" 0 failed", r.stdout)


OMARCHY_PLUGINS = "/usr/share/omarchy/shell/plugins"


def items():
    with open(os.path.join(BAR, "items.json")) as f:
        return json.load(f)["omarchy"]


class Coverage(unittest.TestCase):
    """Every Omarchy bar item has a Fathom dropdown, or a plan for one, now
    and as Omarchy adds items (the user's rule, #14)."""

    def test_each_item_says_one_thing(self):
        for wid, item in items().items():
            said = [k for k in ("fathom", "planned", "none") if k in item]
            self.assertEqual(len(said), 1, f"{wid}: one of fathom, planned or none")

    def test_each_fathom_dropdown_is_a_clone_of_its_item(self):
        for wid, item in items().items():
            plugin = item.get("fathom")
            if not plugin or plugin == "fathom.desk":
                continue
            folder = os.path.join(BAR, "plugin", plugin)
            with open(os.path.join(folder, "manifest.json")) as f:
                manifest = json.load(f)
            self.assertEqual(manifest["id"], plugin)
            self.assertEqual(manifest["omarchy"]["clonedFrom"], wid, plugin)
            self.assertIn("bar-widget", manifest["kinds"])
            entry = os.path.join(folder, manifest["entryPoints"]["barWidget"])
            with open(entry) as f:
                qml = f.read()
            # Omarchy's own name inside, so its keys and scripts reach it.
            self.assertIn(f'moduleName: "{wid}"', qml, plugin)

    def test_every_plugin_in_bar_is_listed(self):
        listed = {i["fathom"] for i in items().values() if "fathom" in i}
        for folder in glob.glob(os.path.join(BAR, "plugin", "*")):
            self.assertIn(os.path.basename(folder), listed)

    def test_every_omarchy_bar_item_is_listed(self):
        """Where Omarchy is installed: a bar item it has that the list
        doesn't name fails here, so a new one gets a Fathom dropdown."""
        if not os.path.isdir(OMARCHY_PLUGINS):
            self.skipTest("Omarchy isn't installed here")
        found = set()
        for path in glob.glob(os.path.join(OMARCHY_PLUGINS, "**", "*manifest.json"), recursive=True):
            with open(path) as f:
                manifest = json.load(f)
            if "bar-widget" in manifest.get("kinds", []):
                found.add(manifest["id"])
        self.assertTrue(found, "Omarchy's bar items were found")
        missing = sorted(found - set(items()))
        self.assertEqual(missing, [], "Omarchy bar items with no line in bar/items.json")


class Install(unittest.TestCase):
    """install.sh --desk swaps a Fathom dropdown in for an Omarchy item on
    the bar, in its place and with its settings; uninstall.sh puts
    Omarchy's back. In the sandbox of install_env.py, whose `omarchy` does
    to shell.json what Omarchy does for a clone."""

    LAYOUT = [{"id": "omarchy.tray"}, {"id": "omarchy.monitor", "note": "kept"}, {"id": "omarchy.clock"}]

    def setUp(self):
        from install_env import Sandbox
        self.box = Sandbox()
        self.addCleanup(self.box.cleanup)

    def bar(self, right):
        path = self.box.path(".config", "omarchy", "shell.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump({"bar": {"layout": {"left": [], "right": right}}}, f)

    def right(self):
        with open(self.box.path(".config", "omarchy", "shell.json")) as f:
            return json.load(f)["bar"]["layout"]["right"]

    def test_display_takes_the_monitor_s_place_and_gives_it_back(self):
        self.bar(self.LAYOUT)
        r = self.box.run("install.sh", "--desk")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.right(), [{"id": "omarchy.tray"}, {"id": "fathom.display", "note": "kept"},
                                        {"id": "omarchy.clock"}, {"id": "fathom.desk"}])
        plugin = self.box.path(".config", "omarchy", "plugins", "fathom.display")
        self.assertTrue(os.path.isfile(os.path.join(plugin, "kit", "DropCard.qml")), "the kit goes in as kit/")
        self.assertIn("Fathom's dropdowns on the bar: fathom.display.", r.stdout)
        self.assertIn("Bar items without a Fathom dropdown yet: omarchy.clock, omarchy.tray.", r.stdout)
        r = self.box.run("uninstall.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.right(), self.LAYOUT)
        self.assertFalse(os.path.exists(plugin))

    def test_no_monitor_on_the_bar_no_display(self):
        self.bar([{"id": "omarchy.clock"}])
        r = self.box.run("install.sh", "--desk")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("omarchy plugin enable fathom.display", self.box.calls())
        self.assertFalse(os.path.exists(self.box.path(".config", "omarchy", "plugins", "fathom.display")))


if __name__ == "__main__":
    unittest.main()

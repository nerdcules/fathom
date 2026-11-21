"""Fathom's bar dropdowns (#14): each Omarchy bar item gets a Fathom one.

Each dropdown is drawn by the kit's factory from a description its plugin
gives (bar/README.md). The QML test runs the factory offscreen with the kit
beside it as kit/, as install.sh puts it; tests/bar.test.mjs checks each
plugin's description.
"""

import glob
import hashlib
import json
import re
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
        shutil.copytree(os.path.join(REPO, "kit"), os.path.join(tmp, "kit"))
        shutil.copy(os.path.join(REPO, "tests", "qml", "bar", "tst_drop_sections.qml"), tmp)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        r = subprocess.run([qmltestrunner(), "-input", os.path.join(tmp, "tst_drop_sections.qml")],
                           env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])
        self.assertIn(" 0 failed", r.stdout)


class Cards(unittest.TestCase):
    """A dropdown's own parts, beside the factory's, in the plugin folder as
    install.sh stages it (the plugin, with the kit inside as kit/)."""

    def run_staged(self, plugin_id, test_file):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        dest = os.path.join(tmp, plugin_id)
        # The plugin's kit/ is a link to the repo's kit; the copy follows it.
        shutil.copytree(os.path.join(BAR, "plugin", plugin_id), dest)
        shutil.copy(os.path.join(REPO, "tests", "qml", "bar", test_file), tmp)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        r = subprocess.run([qmltestrunner(), "-input", os.path.join(tmp, test_file)],
                           env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])
        self.assertIn(" 0 failed", r.stdout)

    def test_clock_month(self):
        self.run_staged("fathom.clock", "tst_month_grid.qml")


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

    def test_each_fathom_dropdown_says_what_it_follows(self):
        for wid, item in items().items():
            if "fathom" in item:
                self.assertTrue(item.get("follows"), f"{wid}: the Omarchy files its Fathom dropdown copies")

    def test_nothing_followed_has_changed(self):
        """Where Omarchy is installed: each Omarchy file a dropdown copies
        behaviour from is as it was when the dropdown was last checked
        against it. When Omarchy changes one, review the dropdown against
        the change, then write the new fingerprint into bar/items.json."""
        if not os.path.isdir(OMARCHY_PLUGINS):
            self.skipTest("Omarchy isn't installed here")
        with open(os.path.join(BAR, "items.json")) as f:
            data = json.load(f)
        followed = [("the popup frame", data.get("kitFollows", {}))]
        followed += [(i["fathom"] + " (" + wid + ")", i.get("follows", {})) for wid, i in data["omarchy"].items() if "fathom" in i]
        changed = []
        for who, files in followed:
            for path, want in files.items():
                full = os.path.join("/usr/share/omarchy", path)
                if not os.path.isfile(full):
                    changed.append(f"{who}: {path} is gone")
                    continue
                with open(full, "rb") as f:
                    got = hashlib.sha256(f.read()).hexdigest()[:16]
                if got != want:
                    changed.append(f"{who}: {path} changed ({want} -> {got})")
        self.assertEqual(changed, [], "Omarchy changed what these dropdowns copy; review them (checked with "
                         + data.get("checkedWith", "?") + ")")

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

    def test_omarchys_words_a_dropdown_borrows_exist(self):
        """Where Omarchy is installed: a dropdown can use Omarchy's own words
        (a key starting with "@", in every language Omarchy has); each one
        it asks for is in Omarchy's English catalog."""
        catalog = "/usr/share/omarchy/default/i18n/en/shell.json"
        if not os.path.isfile(catalog):
            self.skipTest("Omarchy isn't installed here")
        with open(catalog) as f:
            data = json.load(f)
        def has(key):
            return isinstance(data.get(key), str)
        missing, used = [], 0
        for path in glob.glob(os.path.join(BAR, "plugin", "*", "*.js")) + glob.glob(os.path.join(BAR, "plugin", "*", "*.qml")):
            with open(path) as f:
                for key in re.findall(r'\bt\("@([a-zA-Z][\w.]*)"\)', f.read()):
                    used += 1
                    if not has(key):
                        missing.append(f"{os.path.relpath(path, BAR)}: {key}")
        self.assertGreater(used, 0)
        self.assertEqual(missing, [])


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

    def test_dropdowns_take_their_items_places_and_give_them_back(self):
        self.bar(self.LAYOUT)
        r = self.box.run("install.sh", "--desk")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.right(), [{"id": "omarchy.tray"}, {"id": "fathom.display", "note": "kept"},
                                        {"id": "fathom.clock"}, {"id": "fathom.desk"}])
        plugin = self.box.path(".config", "omarchy", "plugins", "fathom.display")
        self.assertTrue(os.path.isfile(os.path.join(plugin, "kit", "DropCard.qml")), "the kit goes in as kit/")
        self.assertFalse(os.path.islink(os.path.join(plugin, "kit")), "a copy, not the repo's link")
        self.assertIn("Fathom's dropdowns on the bar: fathom.display fathom.clock.", r.stdout)
        self.assertIn("Bar items without a Fathom dropdown yet: omarchy.tray.", r.stdout)
        r = self.box.run("uninstall.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.right(), self.LAYOUT)
        self.assertFalse(os.path.exists(plugin))

    def test_no_monitor_on_the_bar_no_display(self):
        self.bar([{"id": "omarchy.weather"}])
        r = self.box.run("install.sh", "--desk")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("omarchy plugin enable fathom.display", self.box.calls())
        self.assertFalse(os.path.exists(self.box.path(".config", "omarchy", "plugins", "fathom.display")))


if __name__ == "__main__":
    unittest.main()

"""The bar's cluster (#14): install.sh --desk swaps Omarchy's Bluetooth,
network, volume and battery widgets for Fathom's one button, keeping where
they were, and uninstall.sh puts them back. Run in the sandbox of
install_env.py, whose `omarchy` records its calls and edits shell.json's bar
as Omarchy does for plugin enable and disable."""

import json
import os
import unittest

from install_env import Sandbox

FOUR = ["omarchy.bluetooth", "omarchy.network", "omarchy.audio", "omarchy.power"]


class Cluster(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()
        self.addCleanup(self.box.cleanup)

    def bar(self, right, left=None):
        path = self.box.path(".config", "omarchy", "shell.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump({"bar": {"layout": {"left": left or [{"id": "omarchy.menu"}], "right": right}}}, f)

    def run_ok(self, script, *args):
        r = self.box.run(script, *args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def right(self):
        with open(self.box.path(".config", "omarchy", "shell.json")) as f:
            return [e if isinstance(e, str) else e["id"] for e in json.load(f)["bar"]["layout"]["right"]]

    def plugin_calls(self):
        # The monitor on these bars gets Fathom's Display too (#14), which
        # test_bar.py checks; these are about the cluster.
        return [c for c in self.box.calls() if (c.startswith("omarchy plugin ") or c.startswith("omarchy bar set"))
                and "fathom.display" not in c]

    def kept(self):
        path = self.box.path(".local", "state", "fathom", "desk-cluster")
        if not os.path.exists(path):
            return None
        with open(path) as f:
            return json.load(f)

    LAYOUT = [{"id": "seunarayan.sysmon"}, {"id": "omarchy.tray"}, {"id": "omarchy.bluetooth"},
              {"id": "omarchy.network"}, {"id": "omarchy.audio", "showPercent": True},
              {"id": "omarchy.monitor"}, {"id": "omarchy.power"}]

    def test_install_puts_the_cluster_after_the_last_and_takes_the_four_off(self):
        self.bar(self.LAYOUT)
        r = self.run_ok("install.sh", "--desk")
        calls =[c for c in self.plugin_calls() if not c.startswith("omarchy plugin validate")]
        self.assertEqual(calls, [
            "omarchy plugin enable fathom.desk --after omarchy.power",
            "omarchy plugin disable omarchy.bluetooth",
            "omarchy plugin disable omarchy.network",
            "omarchy plugin disable omarchy.audio",
            "omarchy plugin disable omarchy.power",
        ])
        self.assertEqual([(e["id"], e["section"], e["index"]) for e in self.kept()],
                         [("omarchy.bluetooth", "right", 2), ("omarchy.network", "right", 3),
                          ("omarchy.audio", "right", 4), ("omarchy.power", "right", 6)])
        self.assertEqual(self.kept()[2]["entry"], {"id": "omarchy.audio", "showPercent": True})
        self.assertIn("one button on the bar", r.stdout)

    def test_an_upgrade_leaves_the_cluster_where_it_is(self):
        self.bar(self.LAYOUT)
        self.run_ok("install.sh", "--desk")
        first = self.kept()
        self.assertEqual(self.right(), ["seunarayan.sysmon", "omarchy.tray", "fathom.display", "fathom.desk"])
        self.box.clear_calls()
        r = self.run_ok("install.sh", "--desk")
        calls = [c for c in self.plugin_calls() if not c.startswith("omarchy plugin validate")]
        self.assertEqual(calls, ["omarchy plugin enable fathom.desk"])
        self.assertEqual(self.kept(), first, "where the four were is kept as it was")
        self.assertNotIn("one button on the bar", r.stdout)

    def test_a_widget_put_back_by_hand_is_taken_off_again_and_kept(self):
        self.bar(self.LAYOUT)
        self.run_ok("install.sh", "--desk")
        self.bar([{"id": "omarchy.network"}, {"id": "omarchy.monitor"}, {"id": "fathom.desk"}])
        self.box.clear_calls()
        self.run_ok("install.sh", "--desk")
        calls = [c for c in self.plugin_calls() if not c.startswith("omarchy plugin validate")]
        self.assertEqual(calls, ["omarchy plugin enable fathom.desk --after omarchy.network",
                                 "omarchy plugin disable omarchy.network"])
        self.assertEqual(self.right(), ["fathom.display", "fathom.desk"], "the cluster stays where it was")
        self.assertEqual(sorted(e["id"] for e in self.kept()), sorted(FOUR), "one record per widget")

    def test_a_bar_without_them_gets_no_cluster_record(self):
        self.bar([{"id": "omarchy.tray"}])
        self.run_ok("install.sh", "--desk")
        calls = [c for c in self.plugin_calls() if not c.startswith("omarchy plugin validate")]
        self.assertEqual(calls, ["omarchy plugin enable fathom.desk"])
        self.assertIsNone(self.kept())

    def test_no_shell_json_is_no_bar_to_change(self):
        self.run_ok("install.sh", "--desk")
        calls = [c for c in self.plugin_calls() if not c.startswith("omarchy plugin validate")]
        self.assertEqual(calls, ["omarchy plugin enable fathom.desk"])

    def test_uninstall_puts_them_back_where_they_were_with_their_settings(self):
        self.bar(self.LAYOUT)
        self.run_ok("install.sh", "--desk")
        self.box.clear_calls()
        self.run_ok("uninstall.sh")
        calls = self.plugin_calls()
        desk_off = calls.index("omarchy plugin disable fathom.desk")
        self.assertEqual(calls[desk_off + 1:desk_off + 6], [
            "omarchy plugin enable omarchy.bluetooth --section right --index 2",
            "omarchy plugin enable omarchy.network --section right --index 3",
            "omarchy plugin enable omarchy.audio --section right --index 4",
            "omarchy plugin enable omarchy.power --section right --index 6",
            "omarchy bar set omarchy.audio showPercent true --json",
        ])
        self.assertIsNone(self.kept())
        self.assertEqual(self.right(), [e["id"] for e in self.LAYOUT], "the bar as it was")

    def test_uninstall_leaves_no_desk_entry_of_any_kind(self):
        # A desk installed before it had a bar widget has a plugins record;
        # the cluster then adds a bar entry beside it (seen in the test VM).
        self.bar(self.LAYOUT)
        path = self.box.path(".config", "omarchy", "shell.json")
        with open(path) as f:
            shell = json.load(f)
        shell["plugins"] = [{"id": "fathom.desk"}]
        with open(path, "w") as f:
            json.dump(shell, f)
        self.run_ok("install.sh", "--desk")
        self.run_ok("uninstall.sh")
        with open(path) as f:
            text = f.read()
        self.assertNotIn("fathom.desk", text)
        self.assertEqual(self.right(), [e["id"] for e in self.LAYOUT])

    def test_the_four_stay_when_the_cluster_does_not_go_on(self):
        self.bar(self.LAYOUT)
        r = self.box.run("install.sh", "--desk", STUB_NO_PLACE="1")
        self.assertNotIn("omarchy plugin disable omarchy.network", self.box.calls())
        self.assertIn("the bar's cluster didn't go on the bar, so Omarchy's own widgets stay", r.stderr)
        self.assertEqual(self.right(), [e["id"] for e in self.LAYOUT])
        self.assertIsNone(self.kept())


if __name__ == "__main__":
    unittest.main()

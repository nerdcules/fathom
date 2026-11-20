"""The Start menu and Quick settings' list page under real mouse clicks and
keys, through Qt's qmltestrunner (tests/qml/tst_*.qml), offscreen; and no
TapHandler anywhere in Fathom's QML."""

import os
import re
import shutil
import subprocess
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def qmltestrunner():
    for name in ("qmltestrunner6", "qmltestrunner"):
        found = shutil.which(name)
        if found:
            return found
    path = "/usr/lib/qt6/bin/qmltestrunner"
    return path if os.access(path, os.X_OK) else None


@unittest.skipUnless(qmltestrunner(), "needs Qt 6's qmltestrunner")
class StartClicks(unittest.TestCase):
    def run_qml(self, name):
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        r = subprocess.run([qmltestrunner(), "-input", os.path.join(REPO, "tests", "qml", name)],
                           env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])
        self.assertIn(" 0 failed", r.stdout)

    def test_clicks_land_on_one_thing(self):
        self.run_qml("tst_start_clicks.qml")

    def test_quick_settings_list_page(self):
        """Quick settings' Wi-Fi and Bluetooth list page (#14)."""
        self.run_qml("tst_quick_list.qml")


class NoTapHandlers(unittest.TestCase):
    """A TapHandler only grabs a press passively, so a click on one drawn over
    another clicks both (#13: Restart in the power menu also opened the
    Recent project under it). Clickable things use a MouseArea, which keeps
    the click."""

    def test_no_qml_file_uses_a_taphandler(self):
        found = []
        for folder, dirs, files in os.walk(REPO):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("tests", "node_modules")]
            for name in files:
                if not name.endswith(".qml"):
                    continue
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    for n, line in enumerate(f, 1):
                        if re.match(r"\s*TapHandler\s*\{", line):
                            found.append(f"{os.path.relpath(path, REPO)}:{n}")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()

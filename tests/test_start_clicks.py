"""The Start menu under real mouse clicks, through Qt's qmltestrunner
(tests/qml/tst_start_clicks.qml), offscreen."""

import os
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
    def test_clicks_land_on_one_thing(self):
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        r = subprocess.run([qmltestrunner(), "-input", os.path.join(REPO, "tests", "qml", "tst_start_clicks.qml")],
                           env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])
        self.assertIn(" 0 failed", r.stdout)


if __name__ == "__main__":
    unittest.main()

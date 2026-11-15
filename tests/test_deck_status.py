"""fathom-deck status, run as the deck runs it."""

import json
import os
import subprocess
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECK = os.path.join(REPO, "deck", "bin", "fathom-deck")


class DisksTest(unittest.TestCase):
    def test_one_unreadable_mount_doesnt_lose_the_rest(self):
        # df prints the mounts it could read and exits 1 when one can't be
        # read, as with a FUSE mount whose program died.
        with tempfile.TemporaryDirectory() as stub:
            df = os.path.join(stub, "df")
            with open(df, "w") as f:
                f.write("#!/bin/sh\n"
                        "echo 'Filesystem Mounted-on 1B-blocks Used Avail'\n"
                        "echo '/dev/test / 1000 400 600'\n"
                        "echo 'df: /tmp/gone: Transport endpoint is not connected' >&2\n"
                        "exit 1\n")
            os.chmod(df, 0o755)
            env = dict(os.environ, PATH=stub + os.pathsep + os.environ["PATH"])
            out = subprocess.run([DECK, "status"], capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        disks = json.loads(out.stdout)["system"]["disks"]
        self.assertEqual(disks, [{"mount": "/", "size": 1000, "used": 400, "free": 600}])


if __name__ == "__main__":
    unittest.main()

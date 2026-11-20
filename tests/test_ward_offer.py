"""The offer to set up Ward (github.com/nerdcules/ward), and what Fathom shows
once it is: `fathom-care ward`, Care's warnings, Sentinel's status and the
question install.sh asks. Ward, nerdcules-update and systemctl are stand-ins;
nothing is installed."""

import importlib.machinery
import importlib.util
import json
import os
import pty
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARE = os.path.join(REPO, "care", "bin", "fathom-care")
SENTINEL = os.path.join(REPO, "sentinel", "bin", "fathom-sentinel")


def stub(folder, name, script):
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + script)
    os.chmod(path, 0o755)
    return path


def finding(cve, package, priority="", applies="", kev=False):
    f = {"cve": cve, "package": package, "version": "1.0-1", "verdict": "affected", "kev": kev}
    if applies:
        f.update(applies=applies, priority=priority, triagedBy="claude")
    return f


class WardOffer(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.dir = self._dir.name
        self.bin = os.path.join(self.dir, "bin")
        os.mkdir(self.bin)
        self.home = os.path.join(self.dir, "home")
        self.state = os.path.join(self.home, ".state")
        os.makedirs(os.path.join(self.state, "fathom"))
        self.log = os.path.join(self.dir, "calls")
        # Ward isn't installed until a stand-in writes this file.
        self.ward = os.path.join(self.dir, "ward-bin", "ward")
        stub(self.bin, "systemctl", "echo disabled\n")
        self.env = dict(os.environ, HOME=self.home, XDG_STATE_HOME=self.state, FATHOM_WARD=self.ward,
                        PATH=self.bin + os.pathsep + os.environ["PATH"], CALLS=self.log)

    def tearDown(self):
        self._dir.cleanup()

    def care(self, *args, stdin=None):
        return subprocess.run([CARE, *args], capture_output=True, text=True, env=self.env, input=stdin, timeout=60)

    def ward_status(self):
        out = self.care("ward", "status")
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def install_ward_stub(self):
        os.makedirs(os.path.dirname(self.ward), exist_ok=True)
        stub(os.path.dirname(self.ward), "ward", 'echo "ward $*" >> "$CALLS"\n')

    def write_findings(self, findings, kernels=()):
        os.makedirs(os.path.join(self.state, "ward"), exist_ok=True)
        with open(os.path.join(self.state, "ward", "findings.json"), "w") as f:
            json.dump({"checkedAt": "2026-11-20T12:00:00Z", "findings": findings, "kernels": list(kernels)}, f)

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return f.read().splitlines()

    # ------------------------------------------------ status

    def test_not_installed(self):
        s = self.ward_status()
        self.assertEqual(s, {"installed": False, "scheduled": False, "dismissed": False, "results": None})

    def test_what_the_last_check_found(self):
        self.install_ward_stub()
        stub(self.bin, "systemctl", "echo enabled\n")
        self.write_findings(
            [finding("CVE-1", "openssh", "now", "yes"),
             finding("CVE-2", "openssh", "later", "no", kev=True),   # exploited, but ruled out
             finding("CVE-3", "glibc", "soon", "unclear", kev=True),
             finding("CVE-4", "ffmpeg"),                             # not triaged
             finding("CVE-6", "python:3.8", "later", "unclear", kev=True),  # exploited, settled as later
             dict(finding("CVE-5", "x"), verdict="unknown")],        # versions unreadable
            kernels=[{"package": "linux", "branch": "7.2", "eol": True, "stable": "7.3.5"}])
        s = self.ward_status()
        self.assertTrue(s["installed"])
        self.assertTrue(s["scheduled"])
        self.assertEqual(s["results"], {"checkedAt": "2026-11-20T12:00:00Z", "affected": 5, "packages": 4,
                                        "now": 1, "soon": 1, "open": 1, "exploited": 1,
                                        "kernel": {"package": "linux", "branch": "7.2", "stable": "7.3.5"}})

    def test_a_broken_results_file(self):
        os.makedirs(os.path.join(self.state, "ward"))
        with open(os.path.join(self.state, "ward", "findings.json"), "w") as f:
            f.write("{not json")
        self.assertIsNone(self.ward_status()["results"])

    def test_not_now_is_remembered(self):
        self.assertEqual(self.care("ward", "dismiss").returncode, 0)
        self.assertTrue(self.ward_status()["dismissed"])

    # ------------------------------------------------ Care's warnings

    def care_warnings(self):
        out = self.care("status")
        self.assertEqual(out.returncode, 0, out.stderr)
        return [w for w in json.loads(out.stdout)["warnings"] if w["kind"].startswith("ward")]

    def test_care_offers_ward_until_not_now(self):
        self.assertEqual(self.care_warnings(), [{"kind": "ward-setup"}])
        self.care("ward", "dismiss")
        self.assertEqual(self.care_warnings(), [])

    def test_care_passes_on_what_needs_you_now(self):
        self.install_ward_stub()
        self.write_findings([finding("CVE-1", "openssh", "now", "yes"), finding("CVE-2", "git", "now", "yes")])
        self.assertEqual(self.care_warnings(), [{"kind": "ward", "now": 2}])

    def test_nothing_urgent_no_warning(self):
        self.install_ward_stub()
        self.write_findings([finding("CVE-1", "openssh", "later", "no")])
        self.assertEqual(self.care_warnings(), [])

    # ------------------------------------------------ setting it up

    def nerdcules_update(self, published='["v0.1.0-rc.1"]'):
        # apply finds nothing on the stable channel (as with only a
        # pre-release); install puts the stand-in ward in place.
        stub(self.bin, "nerdcules-update", f"""echo "nerdcules-update $*" >> "$CALLS"
case "$1" in
  apply) echo "ward is up to date (no stable release yet; pre-releases need the prerelease channel)." ;;
  versions) echo '{{"app": "ward", "channel": "stable", "published": {published}, "kept": []}}' ;;
  install) mkdir -p "$(dirname "$FATHOM_WARD")"; printf '#!/bin/sh\\necho "ward $*" >> "$CALLS"\\n' > "$FATHOM_WARD"; chmod +x "$FATHOM_WARD" ;;
esac
""")

    def test_setup_takes_the_pre_release_when_asked(self):
        self.nerdcules_update()
        self.care("ward", "dismiss")
        out = self.care("ward", "install", stdin="y\nn\n")   # yes to the pre-release, no to a first check
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertEqual(self.calls(), ["nerdcules-update apply ward", "nerdcules-update versions ward --json",
                                        "nerdcules-update install ward v0.1.0-rc.1", "ward schedule on"])
        self.assertFalse(self.ward_status()["dismissed"])

    def test_setup_stops_at_a_no(self):
        self.nerdcules_update()
        out = self.care("ward", "install", stdin="n\n")
        self.assertEqual(out.returncode, 1)
        self.assertNotIn("nerdcules-update install ward v0.1.0-rc.1", self.calls())
        self.assertFalse(os.path.exists(self.ward))

    def test_setup_with_nothing_published(self):
        self.nerdcules_update(published="[]")
        out = self.care("ward", "install", stdin="")
        self.assertEqual(out.returncode, 1)
        self.assertIn("no release to install", out.stdout)

    def test_setup_when_ward_is_there_only_schedules(self):
        self.install_ward_stub()
        out = self.care("ward", "install", stdin="y\n")      # yes to a first check
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertEqual(self.calls(), ["ward schedule on", "ward check"])

    # ------------------------------------------------ Sentinel

    def sentinel_module(self):
        loader = importlib.machinery.SourceFileLoader("fathom_sentinel_bin", SENTINEL)
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        sys.path.insert(0, os.path.join(REPO, "sentinel"))
        try:
            loader.exec_module(module)
        finally:
            sys.path.remove(os.path.join(REPO, "sentinel"))
        return module

    def test_sentinel_reads_ward_through_care(self):
        m = self.sentinel_module()
        stub(self.bin, "fathom-care",
             'echo \'{"installed": true, "scheduled": true, "dismissed": false, "results": null}\'\n')
        old_path, old_home = os.environ["PATH"], m.HOME
        os.environ["PATH"] = self.bin + os.pathsep + old_path
        try:
            self.assertEqual(m.ward(), {"installed": True, "scheduled": True, "dismissed": False, "results": None})
            stub(self.bin, "fathom-care", "echo nonsense\n")
            self.assertIsNone(m.ward())
            # No Care anywhere: no row.
            os.remove(os.path.join(self.bin, "fathom-care"))
            os.environ["PATH"] = self.bin
            m.HOME = self.home
            self.assertIsNone(m.ward())
        finally:
            os.environ["PATH"] = old_path
            m.HOME = old_home

    # ------------------------------------------------ install.sh's question

    def offer(self, answer, tty=True):
        """Runs install.sh's offer_ward on its own, in a terminal when `tty`."""
        with open(os.path.join(REPO, "install.sh")) as f:
            text = f.read()
        start = text.index("offer_ward() {")
        body = text[start:text.index("\n}\n", start) + 3]
        script = f'STATE_DIR={self.state}/fathom\nREPO={REPO}\n{body}\noffer_ward\n'
        env = dict(self.env)
        if not tty:
            return subprocess.run(["bash", "-c", script], input=answer, capture_output=True, text=True,
                                  env=env, timeout=60).stdout
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe("bash", ["bash", "-c", script], env)
        os.write(fd, answer.encode())
        out = b""
        while True:
            try:
                chunk = os.read(fd, 1024)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        os.waitpid(pid, 0)
        return out.decode(errors="replace")

    def test_install_asks_once_and_remembers_a_no(self):
        out = self.offer("n\n")
        self.assertIn("Also set up Ward", out)
        self.assertTrue(os.path.exists(os.path.join(self.state, "fathom", "ward-dismissed")))
        self.assertNotIn("Also set up Ward", self.offer("y\n"))   # not asked again

    def test_install_doesnt_ask_without_a_terminal(self):
        self.assertNotIn("Also set up Ward", self.offer("y\n", tty=False))
        self.assertFalse(os.path.exists(os.path.join(self.state, "fathom", "ward-dismissed")))

    def test_install_doesnt_ask_when_ward_is_there(self):
        self.install_ward_stub()
        # offer_ward looks for `ward` on the PATH.
        shutil.copy(self.ward, os.path.join(self.bin, "ward"))
        self.assertNotIn("Also set up Ward", self.offer("y\n"))


if __name__ == "__main__":
    unittest.main()

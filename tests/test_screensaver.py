"""Fathom's screensaver (./install.sh --screensaver): fathom-screensaver's
choice between Blueprint and Omarchy's own, the install and uninstall in the
sandbox (tests/install_env.py), with Omarchy's idle service cloned as
fathom.idle and only its screensaver line changed, and Blueprint itself
built for real and run through its own tests."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

from install_env import REPO, Sandbox

LAUNCHER = os.path.join(REPO, "screensaver", "bin", "fathom-screensaver")

# Omarchy's idle service, cut down to the line that matters.
STOCK_LINE = ('    runProcess(screensaverProcess, "screensaver", "[[ $(omarchy-shell lock isLocked 2>/dev/null) '
              '== \\"true\\" ]] || omarchy-launch-screensaver")\n')
OURS_LINE = STOCK_LINE.replace("|| omarchy-launch-screensaver", "|| $HOME/.local/bin/fathom-screensaver")
SERVICE = "import QtQuick\n\nItem {\n  function screensaver() {\n" + STOCK_LINE + "  }\n}\n"
MANIFEST = {"schemaVersion": 1, "id": "omarchy.idle", "name": "Idle", "version": "1.0.0", "author": "Omarchy",
            "kinds": ["service"], "keepLoaded": True, "entryPoints": {"service": "Service.qml"}}


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def read(path):
    with open(path) as f:
        return f.read()


class Launcher(unittest.TestCase):
    """fathom-screensaver with stand-ins for Omarchy and Hyprland."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = os.path.join(self.tmp, "bin")
        self.log = os.path.join(self.tmp, "calls")
        self.blueprint = os.path.join(self.tmp, "blueprint")
        log = f'echo "$(basename "$0") $*" >> {self.log}\n'
        for name in ("omarchy-launch-screensaver", "pgrep"):
            write(os.path.join(self.bin, name), "#!/bin/sh\n" + log + "exit 1\n", 0o755)
        write(os.path.join(self.bin, "omarchy-toggle-enabled"), "#!/bin/sh\n[ -e \"$OFF\" ]\n", 0o755)
        write(os.path.join(self.bin, "omarchy-hyprland-monitor-focused"), "#!/bin/sh\necho DP-1\n", 0o755)
        # Two monitors; each window opens as soon as it is asked for.
        write(os.path.join(self.bin, "hyprctl"), "#!/bin/sh\n" + log + """case "$1 $2" in
  "monitors -j") echo '[{"name":"DP-1","specialWorkspace":{"name":""}},{"name":"HDMI-A-1","specialWorkspace":{"name":""}}]' ;;
  "clients -j") echo '[]' ;;
esac
""", 0o755)
        write(os.path.join(self.bin, "socat"),
              "#!/bin/sh\nfor i in 1 2; do echo 'openwindow>>a,special:x,org.omarchy.screensaver,t'; done\nsleep 1\n", 0o755)
        self.env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"],
                        XDG_CONFIG_HOME=os.path.join(self.tmp, "config"), FATHOM_BLUEPRINT=self.blueprint,
                        XDG_RUNTIME_DIR=self.tmp, HYPRLAND_INSTANCE_SIGNATURE="x", OFF=os.path.join(self.tmp, "off"))

    def run_it(self, *args):
        return subprocess.run([LAUNCHER, *args], env=self.env, capture_output=True, text=True, timeout=30)

    def calls(self):
        return read(self.log).splitlines() if os.path.exists(self.log) else []

    def install_blueprint(self):
        write(self.blueprint, "#!/bin/sh\nexit 0\n", 0o755)

    def test_what_it_shows(self):
        self.assertEqual(self.run_it("shows").stdout, "omarchy\n")       # no Blueprint here
        self.assertNotEqual(self.run_it("shows", "blueprint").returncode, 0)
        self.install_blueprint()
        self.assertEqual(self.run_it("shows").stdout, "blueprint\n")     # Blueprint unless told otherwise
        self.assertEqual(self.run_it("shows", "omarchy").returncode, 0)
        self.assertEqual(self.run_it("shows").stdout, "omarchy\n")
        self.assertEqual(self.run_it("shows", "nonsense").returncode, 2)
        self.assertEqual(self.run_it("shows").stdout, "omarchy\n")
        self.assertEqual(self.run_it("shows", "blueprint").returncode, 0)
        self.assertEqual(self.run_it("shows").stdout, "blueprint\n")

    def test_omarchys_own_goes_to_omarchys_launcher(self):
        self.run_it("force")
        self.assertEqual(self.calls(), ["omarchy-launch-screensaver force"])

    def test_blueprint_on_every_monitor(self):
        self.install_blueprint()
        r = self.run_it()
        self.assertEqual(r.returncode, 0, r.stderr)
        started = [c for c in self.calls() if "--screensaver" in c]
        self.assertEqual(len(started), 2, self.calls())
        self.assertIn("[workspace special:screensaver-DP-1]", started[0])
        self.assertIn("[workspace special:screensaver-HDMI-A-1]", started[1])
        self.assertIn(self.blueprint + " --screensaver --app-id org.omarchy.screensaver", started[0])
        self.assertNotIn("omarchy-launch-screensaver", " ".join(self.calls()))

    def test_turned_off_unless_forced(self):
        self.install_blueprint()
        write(self.env["OFF"], "")
        self.assertEqual(self.run_it().returncode, 1)
        self.assertEqual([c for c in self.calls() if "--screensaver" in c], [])
        self.assertEqual(self.run_it("force").returncode, 0)
        self.assertEqual(len([c for c in self.calls() if "--screensaver" in c]), 2)


class Install(unittest.TestCase):
    """install.sh --screensaver and uninstall.sh in the sandbox. qmake6 and
    make are stand-ins: make leaves a script where Blueprint would be."""

    def setUp(self):
        self.box = Sandbox()
        self.addCleanup(self.box.cleanup)
        for tool in ("perl", "install", "nproc", "pkill"):
            os.symlink(shutil.which(tool, path="/usr/bin:/bin"), os.path.join(self.box.bin, tool))
        self.idle = os.path.join(self.box.tmp, "omarchy", "idle")
        write(os.path.join(self.idle, "Service.qml"), SERVICE)
        write(os.path.join(self.idle, "IdleModel.js"), ".pragma library\n")
        write(os.path.join(self.idle, "manifest.json"), json.dumps(MANIFEST))
        log = 'echo "$(basename "$0") $*" >> "$STUB_STATE/calls.log"\n'
        stubs = {
            "qmake6": log,
            "g++": log,
            "make": log + '[ -n "$MAKE_FAILS" ] && { echo "error: it broke" >&2; exit 2; }\n'
                          'printf \'#!/bin/sh\\nexit 0\\n\' > blueprint && chmod +x blueprint\n',
            "omarchy-plugin-catalog": f"""cat <<'EOF'\n{json.dumps([{"id": "omarchy.idle", "firstParty": True,
                                                                     "sourceDir": self.idle}])}\nEOF\n""",
        }
        for name, body in stubs.items():
            write(os.path.join(self.box.bin, name), "#!/bin/sh\n" + body, 0o755)
        self.plugin = self.box.path(".config", "omarchy", "plugins", "fathom.idle")
        self.blueprint = self.box.path(".local", "share", "fathom", "blueprint", "blueprint")

    def install(self, **env):
        return self.box.run("install.sh", "--screensaver", **env)

    def test_install_and_uninstall(self):
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.access(self.blueprint, os.X_OK))
        self.assertTrue(os.path.exists(self.box.path(".local", "bin", "fathom-screensaver")))
        manifest = json.loads(read(os.path.join(self.plugin, "manifest.json")))
        self.assertEqual((manifest["id"], manifest["name"], manifest["omarchy"]["clonedFrom"]),
                         ("fathom.idle", "Fathom Idle", "omarchy.idle"))
        # Every file as Omarchy's, but for the one line.
        self.assertEqual(read(os.path.join(self.plugin, "Service.qml")), SERVICE.replace(STOCK_LINE, OURS_LINE))
        self.assertEqual(read(os.path.join(self.plugin, "IdleModel.js")), ".pragma library\n")
        self.assertIn("omarchy plugin enable fathom.idle", self.box.calls())
        self.assertIn("screensaver", read(self.box.path(".local", "state", "fathom", "installed")).split())

        self.box.clear_calls()
        r = self.box.run("uninstall.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("omarchy plugin disable fathom.idle", self.box.calls())
        for gone in (self.plugin, self.blueprint, self.box.path(".local", "bin", "fathom-screensaver")):
            self.assertFalse(os.path.exists(gone), gone)

    def test_your_own_idle_service_is_left_alone(self):
        # Known from the files alone: the running shell may not answer (it
        # didn't once, just after --skin switched the theme).
        write(self.box.path(".config", "omarchy", "plugins", "me.idle", "manifest.json"),
              json.dumps({"id": "me.idle", "omarchy": {"clonedFrom": "omarchy.idle"}}))
        write(self.box.path(".config", "omarchy", "shell.json"),
              json.dumps({"plugins": [{"id": "fathom.deck"}, {"id": "me.idle"}]}))
        write(os.path.join(self.box.bin, "omarchy-plugin-list"), "#!/bin/sh\nexit 1\n", 0o755)
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("your own idle service (me.idle)", r.stdout)
        self.assertTrue(os.access(self.blueprint, os.X_OK))
        self.assertFalse(os.path.exists(self.plugin))
        self.assertNotIn("omarchy plugin enable fathom.idle", self.box.calls())

    def test_a_copy_you_turned_off_doesnt_count(self):
        write(self.box.path(".config", "omarchy", "plugins", "me.idle", "manifest.json"),
              json.dumps({"id": "me.idle", "omarchy": {"clonedFrom": "omarchy.idle"}}))
        write(self.box.path(".config", "omarchy", "shell.json"), json.dumps({"plugins": [{"id": "fathom.deck"}]}))
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("omarchy plugin enable fathom.idle", self.box.calls())

    def test_an_idle_service_that_changed_isnt_cloned(self):
        write(os.path.join(self.idle, "Service.qml"), SERVICE.replace("omarchy-launch-screensaver", "something-new"))
        r = self.install()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no longer starts the screensaver the way Fathom expects", r.stderr)
        self.assertFalse(os.path.exists(self.plugin))
        self.assertNotIn("omarchy plugin enable fathom.idle", self.box.calls())

    def test_a_build_that_fails_keeps_the_blueprint_you_had(self):
        write(self.blueprint, "#!/bin/sh\necho old\n", 0o755)
        r = self.install(MAKE_FAILS="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Blueprint didn't build", r.stderr)
        self.assertEqual(read(self.blueprint), "#!/bin/sh\necho old\n")
        self.assertFalse(os.path.exists(self.plugin))


@unittest.skipUnless(shutil.which("qmake6") and shutil.which("make"), "needs qmake6 and make")
class Blueprint(unittest.TestCase):
    """Blueprint built from screensaver/blueprint as install.sh builds it, its
    check of the diagrams, and its own Qt Test suite."""

    def test_it_builds_checks_its_diagrams_and_passes_its_tests(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        src = os.path.join(REPO, "screensaver", "blueprint")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        jobs = f"-j{os.cpu_count() or 1}"
        for project, folder in (("blueprint.pro", "app"), (os.path.join("tests", "blueprint_tests.pro"), "tests")):
            out = os.path.join(tmp, folder)
            os.makedirs(out)
            for cmd in (["qmake6", os.path.join(src, project)], ["make", jobs]):
                r = subprocess.run(cmd, cwd=out, capture_output=True, text=True, timeout=600)
                self.assertEqual(r.returncode, 0, r.stderr[-2000:])
        r = subprocess.run([os.path.join(tmp, "app", "blueprint"), "check"], env=env,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        r = subprocess.run([os.path.join(tmp, "tests", "blueprint_tests")], env=env,
                           capture_output=True, text=True, timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:] + r.stderr[-2000:])


if __name__ == "__main__":
    unittest.main()

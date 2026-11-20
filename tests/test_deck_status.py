"""fathom-deck status and fathom-care, run with stand-ins for the tools they
read, so one odd answer from one tool can be shown not to blank a page."""

import json
import os
import subprocess
import tempfile
import time
import re
import unittest

from test_desk import ADDRESSES, IP_ADDR, ip_stub

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECK = os.path.join(REPO, "deck", "bin", "fathom-deck")
CARE = os.path.join(REPO, "care", "bin", "fathom-care")


def stub(folder, name, script):
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + script)
    os.chmod(path, 0o755)


class Stubbed(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.dir = self._dir.name
        self.bin = os.path.join(self.dir, "bin")
        os.mkdir(self.bin)
        # No Ollama, whatever this machine runs.
        stub(self.bin, "curl", "exit 7\n")

    def tearDown(self):
        self._dir.cleanup()

    def run_tool(self, tool, *args, env=None, timeout=60):
        e = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"])
        e.update(env or {})
        return subprocess.run([tool, *args], capture_output=True, text=True, env=e, timeout=timeout)

    def deck(self, env=None, timeout=60):
        out = self.run_tool(DECK, "status", env=env, timeout=timeout)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)


class DeckTest(Stubbed):
    def test_one_unreadable_mount_doesnt_lose_the_rest(self):
        # df prints the mounts it could read and exits 1 when one can't be
        # read, as with a FUSE mount whose program died.
        stub(self.bin, "df", "echo 'Filesystem Mounted-on 1B-blocks Used Avail'\n"
                             "echo '/dev/test / 1000 400 600'\n"
                             "echo 'df: /tmp/gone: Transport endpoint is not connected' >&2\n"
                             "exit 1\n")
        disks = self.deck()["system"]["disks"]
        self.assertEqual(disks, [{"mount": "/", "size": 1000, "used": 400, "free": 600}])

    def test_a_gpu_it_cant_read(self):
        # A card with neither Intel's idle counter nor AMD's busy percent
        # (NVIDIA, a virtual machine).
        drm = os.path.join(self.dir, "drm")
        os.makedirs(os.path.join(drm, "card0", "device"))
        status = self.deck(env={"FATHOM_DECK_DRM": drm})
        self.assertIsNone(status["system"]["gpu"])
        self.assertIsNotNone(status["system"]["cpu"])

    def test_a_cut_off_line_from_docker(self):
        # docker stats stopped by its time limit partway through a line.
        stub(self.bin, "docker", """case "$1" in
  ps) echo '{"name":"web","state":"running","status":"Up","image":"nginx","ports":"","project":"shop"}' ;;
  stats) echo '{"name":"web","cpu":"1.5%","mem":"20MiB / 1GiB"}'; printf '{"name":"db","cpu":' ;;
  system) echo '{"type":"Images","size":"1GB","reclaimable":"0B"}' ;;
esac
""")
        docker = self.deck()["docker"]
        self.assertEqual(docker["state"], "ok")
        self.assertEqual([(c["name"], c["cpu"]) for c in docker["containers"]], [("web", "1.5%")])

    def test_not_json_from_ollamas_port(self):
        # Something else on 11434 answering with a page, not JSON.
        stub(self.bin, "curl", "echo '<html>hello</html>'\n")
        self.assertIsNone(self.deck()["ai"]["ollama"])

    def test_this_machines_addresses(self):
        net = ip_stub(self.bin, IP_ADDR)
        self.assertEqual(self.deck(env={"FATHOM_NET": net})["system"]["addresses"], ADDRESSES)
        stub(self.bin, "ip", "echo nonsense\n")
        self.assertIsNone(self.deck()["system"]["addresses"])

    def test_the_desk_reads_addresses_the_same_way(self):
        # The deck and the desk install apart, so each has its own copy.
        def reader(path):
            with open(path) as f:
                body = re.search(r"^addresses_json\(\) \{\n.*?^\}\n", f.read(), re.M | re.S)
            self.assertIsNotNone(body, path)
            return body.group(0)
        self.assertEqual(reader(DECK), reader(os.path.join(REPO, "desk", "bin", "fathom-desk")))

    def test_a_docker_that_doesnt_answer(self):
        stub(self.bin, "docker", "exec sleep 60\n")
        started = time.monotonic()
        status = self.deck(timeout=30)
        self.assertEqual(status["docker"]["state"], "down")
        self.assertLess(time.monotonic() - started, 15)


class ClaudeStatusTest(Stubbed):
    """The AI card takes Claude Code's own busy/idle over a CPU guess."""

    def start_claude(self):
        # A process the deck finds by name, like the real one.
        fake = os.path.join(self.bin, "claude")
        with open("/usr/bin/sleep", "rb") as src, open(fake, "wb") as dst:
            dst.write(src.read())
        os.chmod(fake, 0o755)
        proc = subprocess.Popen([fake, "60"])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        for _ in range(50):
            try:
                with open(f"/proc/{proc.pid}/comm") as f:
                    if f.read().strip() == "claude":
                        break
            except OSError:
                pass
            time.sleep(0.02)
        with open(f"/proc/{proc.pid}/stat") as f:
            stat = f.read()
        return proc.pid, stat[stat.rindex(")") + 2:].split()[19]

    def status_of(self, pid, session):
        root = os.path.join(self.dir, "claude-config")
        os.makedirs(os.path.join(root, "sessions"), exist_ok=True)
        with open(os.path.join(root, "sessions", f"{pid}.json"), "w") as f:
            json.dump(session, f)
        agents = self.deck(env={"CLAUDE_CONFIG_DIR": root})["ai"]["agents"]
        return [a["status"] for a in agents if a["pid"] == pid]

    def test_its_own_status(self):
        pid, started = self.start_claude()
        self.assertEqual(self.status_of(pid, {"pid": pid, "procStart": started, "status": "busy"}), ["busy"])
        self.assertEqual(self.status_of(pid, {"pid": pid, "procStart": started, "status": "idle"}), ["idle"])

    def test_a_file_from_an_earlier_process_with_the_same_pid(self):
        pid, _ = self.start_claude()
        self.assertEqual(self.status_of(pid, {"pid": pid, "procStart": "1", "status": "busy"}), [None])

    def test_a_status_it_doesnt_know_or_a_broken_file(self):
        pid, started = self.start_claude()
        self.assertEqual(self.status_of(pid, {"pid": pid, "procStart": started, "status": "pondering"}), [None])
        self.assertEqual(self.status_of(pid, ["not", "an", "object"]), [None])


class CareTest(Stubbed):
    def setUp(self):
        super().setUp()
        self.home = os.path.join(self.dir, "home")
        os.mkdir(self.home)
        self.env = {"HOME": self.home, "XDG_STATE_HOME": os.path.join(self.home, ".state"),
                    "XDG_RUNTIME_DIR": self.dir}
        for tool in ("checkupdates", "yay", "docker", "notify-send"):
            stub(self.bin, tool, "exit 0\n")

    def check(self):
        out = self.run_tool(CARE, "check", env=self.env)
        self.assertEqual(out.returncode, 0, out.stderr)
        with open(os.path.join(self.home, ".state", "fathom", "care.json")) as f:
            return json.load(f)

    def test_figures_from_tools_that_then_fail(self):
        # Each prints its answer and then exits with an error.
        stub(self.bin, "fwupdmgr", "echo '{\"Devices\":[{\"Releases\":[{}]}]}'\nexit 2\n")
        stub(self.bin, "paccache", "echo '==> finished dry run: 3 packages (disk space saved: 1.5 GiB)'\nexit 1\n")
        cache = self.check()
        self.assertEqual(cache["updates"]["firmware"], 1)
        pacman = [r for r in cache["reclaim"] if r["id"] == "pacman"]
        self.assertEqual(pacman, [{"id": "pacman", "bytes": 1610612736, "root": True}])

    def test_tools_that_print_nonsense(self):
        stub(self.bin, "fwupdmgr", "echo 'not json'\n")
        stub(self.bin, "paccache", "echo 'something else entirely'\n")
        cache = self.check()
        self.assertEqual(cache["updates"]["firmware"], 0)
        self.assertEqual([r for r in cache["reclaim"] if r["id"] == "pacman"], [])


if __name__ == "__main__":
    unittest.main()


class BriefTest(Stubbed):
    """fathom-deck brief: the bar pill's counts, from the same stand-ins."""

    start_claude = ClaudeStatusTest.start_claude

    def brief(self, env=None, timeout=30):
        out = self.run_tool(DECK, "brief", env=env, timeout=timeout)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def no_agents(self):
        stub(self.bin, "pgrep", "exit 1\n")

    def test_counts_containers_as_the_deck_colours_them(self):
        self.no_agents()
        stub(self.bin, "docker", """[ "$1" = ps ] || exit 1
echo '{"name":"web","state":"running","status":"Up 2 hours","image":"nginx","ports":"","project":""}'
echo '{"name":"api","state":"running","status":"Up 1 hour (unhealthy)","image":"x","ports":"","project":""}'
echo '{"name":"job","state":"exited","status":"Exited (0) 3 days ago","image":"x","ports":"","project":""}'
echo '{"name":"old","state":"exited","status":"Exited (255) 4 days ago","image":"x","ports":"","project":""}'
printf '{"name":"cut'
""")
        docker = self.brief()["docker"]
        self.assertEqual(docker, {"state": "ok", "total": 4, "running": 2, "bad": 2})

    def test_care_and_sentinel_say_what_they_know(self):
        self.no_agents()
        stub(self.bin, "docker", "exit 1\n")
        stub(self.bin, "fathom-care", """echo '{"disk":{"pct":91.7},"warnings":[{"kind":"unit"},{"kind":"disk"},"junk"],
"updates":{"packages":["a","b"],"aur":["c"],"firmware":1,"restart":true}}'
""")
        stub(self.bin, "fathom-sentinel", "echo '{\"attention\": 6}'\n")
        b = self.brief()
        self.assertEqual(b["docker"]["state"], "down")
        self.assertEqual(b["care"], {"warnings": 1, "updates": 4, "diskPct": 91, "restart": True})
        self.assertEqual(b["sentinel"], {"attention": 6})

    def test_care_or_sentinel_missing_odd_or_stuck(self):
        self.no_agents()
        stub(self.bin, "docker", "exit 1\n")
        stub(self.bin, "fathom-care", "echo 'not json'\n")
        stub(self.bin, "fathom-sentinel", "exec sleep 60\n")
        started = time.monotonic()
        b = self.brief()
        self.assertIsNone(b["care"])
        self.assertIsNone(b["sentinel"])
        self.assertLess(time.monotonic() - started, 10)

    def test_claude_codes_own_word_on_working(self):
        stub(self.bin, "docker", "exit 1\n")
        pid, started = self.start_claude()
        stub(self.bin, "pgrep", f'[ "$4" = claude ] && echo {pid}\nexit 0\n')
        root = os.path.join(self.dir, "claude-config")
        os.makedirs(os.path.join(root, "sessions"))
        with open(os.path.join(root, "sessions", f"{pid}.json"), "w") as f:
            json.dump({"pid": pid, "procStart": started, "status": "busy"}, f)
        agents = self.brief(env={"CLAUDE_CONFIG_DIR": root})["agents"]
        self.assertEqual((agents["total"], agents["working"]), (1, 1))
        self.assertEqual(agents["list"][0]["name"], "Claude Code")

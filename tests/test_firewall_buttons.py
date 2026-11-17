"""Sentinel's firewall buttons (sentinel/root/admin) and the uninstall that
takes their rules out (sentinel/install-root.sh uninstall), against a
stand-in ufw (tests/fake_ufw.py) that keeps its rules in a scratch folder.
Nothing here touches the real firewall or runs as root.

The point: only rules with Fathom's comment and shape are Fathom's, and
every other rule, even one that differs only by its comment, stays."""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADMIN = os.path.join(REPO, "sentinel", "root", "admin")
INSTALL_ROOT = os.path.join(REPO, "sentinel", "install-root.sh")
FAKE_UFW = os.path.join(REPO, "tests", "fake_ufw.py")

LOCK = "fathom-lockdown".encode().hex()
BLOCK = "fathom-block".encode().hex()
MINE = "mine".encode().hex()


def tuple_line(fields, comment=""):
    return "### tuple ### " + fields + (f" comment={comment}" if comment else "")


def script(path, body):
    with open(path, "w") as f:
        f.write(body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class FirewallButtons(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = os.path.join(self.tmp, "root")
        self.etc = os.path.join(self.root, "etc")
        os.makedirs(os.path.join(self.etc, "ufw"))
        os.makedirs(os.path.join(self.etc, "default"))
        self.ipv6(True)
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        self.log = os.path.join(self.tmp, "ufw.log")
        script(os.path.join(self.bin, "ufw"), f'#!/bin/sh\nexec {sys.executable} {FAKE_UFW} "$@"\n')
        links = [{"ifname": n} for n in ("lo", "wlan0", "enp3s0", "docker0", "tailscale0")]
        script(os.path.join(self.bin, "ip"), f"#!/bin/sh\necho '{json.dumps(links)}'\n")
        # install-root.sh's other commands: record them, change nothing.
        for cmd in ("systemctl", "pacman"):
            script(os.path.join(self.bin, cmd), f'#!/bin/sh\necho "{cmd} $*" >>{self.tmp}/calls.log\n')
        self.env = dict(os.environ, FATHOM_SENTINEL_ETC=self.etc, FATHOM_SENTINEL_PATH=self.bin,
                        FAKE_UFW_LOG=self.log)

    def ipv6(self, on):
        with open(os.path.join(self.etc, "default", "ufw"), "w") as f:
            f.write(f"IPV6={'yes' if on else 'no'}\n")

    def seed(self, family, *lines):
        path = os.path.join(self.etc, "ufw", "user.rules" if family == 4 else "user6.rules")
        with open(path, "a") as f:
            for line in lines:
                f.write("\n" + line + "\n-A ufw-user-input -j SEEDED\n")

    def rules(self):
        out = []
        for family, name in ((4, "user.rules"), (6, "user6.rules")):
            try:
                with open(os.path.join(self.etc, "ufw", name)) as f:
                    out += [(family, l.strip()) for l in f if l.startswith("### tuple ###")]
            except FileNotFoundError:
                pass
        return out

    def admin(self, *args, env=None):
        return subprocess.run([ADMIN, *args], env=env or self.env, capture_output=True, text=True)

    def ufw_calls(self):
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def users_rules(self):
        """Rules a user might have: some unrelated, all left alone."""
        self.seed(4, tuple_line("allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in"),
                  tuple_line("allow udp 53 172.17.0.1 any 172.16.0.0/12 in", "allow-docker-dns".encode().hex()))
        self.seed(6, tuple_line("allow tcp 22 ::/0 any ::/0 in"))

    # ------------------------------------------------------------ lockdown

    def test_lockdown_on_adds_one_tagged_rule_per_outside_interface_and_family(self):
        self.users_rules()
        r = self.admin("lockdown", "on")
        self.assertEqual(r.returncode, 0, r.stderr)
        rules = self.rules()
        for family, anyw in ((4, "0.0.0.0/0"), (6, "::/0")):
            for iface in ("wlan0", "enp3s0"):
                line = tuple_line(f"deny any any {anyw} any {anyw} in_{iface}", LOCK)
                self.assertEqual(rules.count((family, line)), 1)
            # Prepended: before the user's own rules.
            self.assertTrue(rules[[f for f, _ in rules].index(family)][1].endswith("comment=" + LOCK))
        self.assertFalse(any("docker0" in l or "tailscale0" in l or "_lo " in l for _, l in rules))

    def test_lockdown_on_and_off_cycles_return_to_the_original_rules(self):
        self.users_rules()
        before = self.rules()
        for _ in range(2):
            self.assertEqual(self.admin("lockdown", "on").returncode, 0)
            once = self.rules()
            self.assertEqual(self.admin("lockdown", "on").returncode, 0)
            self.assertEqual(self.rules(), once, "a second 'on' changes nothing")
            r = self.admin("lockdown", "off")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(self.rules(), before)
        # No rule numbers anywhere: every removal names the rule and its comment.
        deletes = [c for c in self.ufw_calls() if c.startswith("delete")]
        self.assertTrue(deletes)
        self.assertTrue(all(c.endswith("comment fathom-lockdown") for c in deletes), deletes)

    def test_lockdown_off_before_on_keeps_a_matching_rule_of_yours(self):
        self.users_rules()
        self.seed(4, tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0"))
        self.seed(6, tuple_line("deny any any ::/0 any ::/0 in_wlan0"))
        before = self.rules()
        r = self.admin("lockdown", "off")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.rules(), before)
        self.assertEqual(self.ufw_calls(), [])
        self.assertIn("kept your own rule 'deny in on wlan0'", r.stderr)

    def test_lockdown_on_refuses_to_take_over_a_rule_that_differs_only_by_action_or_comment(self):
        # ufw would skip Fathom's rule because of these, so off would then
        # have nothing of Fathom's to remove; nothing is changed at all.
        self.seed(4, tuple_line("allow any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0"),
                  tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_enp3s0", MINE))
        before = self.rules()
        r = self.admin("lockdown", "on")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.rules(), before)
        self.assertEqual(self.ufw_calls(), [])
        self.assertIn("allow in on wlan0", r.stderr)
        self.assertIn("deny in on enp3s0 (comment 'mine')", r.stderr)
        self.assertIn("Nothing was changed", r.stderr)
        self.assertIn("sudo ufw status numbered", r.stderr)

    def test_lockdown_off_takes_only_fathoms_copy_of_a_duplicated_rule(self):
        # A rule of yours and Fathom's in the same shape (made by hand: ufw
        # itself won't add the second).
        mine = tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0")
        self.seed(4, tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0", LOCK), mine)
        r = self.admin("lockdown", "off")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.rules(), [(4, mine)])

    def test_lockdown_off_also_ends_it_on_an_interface_that_has_gone(self):
        self.seed(4, tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wwan0", LOCK))
        self.assertEqual(self.admin("lockdown", "off").returncode, 0)
        self.assertEqual(self.rules(), [])

    def test_with_ipv6_off_only_ipv4_rules_are_made(self):
        self.ipv6(False)
        self.assertEqual(self.admin("lockdown", "on").returncode, 0)
        self.assertEqual({f for f, _ in self.rules()}, {4})
        r = self.admin("block", "2001:db8::7")
        self.assertEqual(r.returncode, 3)
        self.assertIn("IPv6 is off", r.stderr)
        self.assertEqual(self.admin("lockdown", "off").returncode, 0)
        self.assertEqual(self.rules(), [])

    # ------------------------------------------------------------ block

    def test_block_and_unblock_cycles_return_to_the_original_rules(self):
        self.users_rules()
        before = self.rules()
        for ip, family in (("203.0.113.7", 4), ("2001:db8::7", 6)):
            for _ in range(2):
                self.assertEqual(self.admin("block", ip).returncode, 0)
                self.assertEqual(self.admin("block", ip).returncode, 0)
                mine = [l for f, l in self.rules() if f == family and l.endswith(BLOCK)]
                self.assertEqual(len(mine), 1, "blocking twice makes one rule")
                r = self.admin("unblock", ip)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(self.rules(), before)

    def test_unblock_before_block_keeps_a_matching_rule_of_yours(self):
        mine = tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in")
        self.seed(4, mine)
        r = self.admin("unblock", "203.0.113.7")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.rules(), [(4, mine)])
        self.assertEqual(self.ufw_calls(), [])
        self.assertIn("still blocked by rules Fathom didn't add", r.stderr)
        # An address nobody blocked: nothing to do.
        r = self.admin("unblock", "198.51.100.1")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(self.rules(), [(4, mine)])

    def test_unblock_takes_fathoms_copy_and_keeps_yours(self):
        # Your rule and Fathom's, the same apart from the comment.
        mine = tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in")
        self.seed(4, mine, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in", BLOCK))
        r = self.admin("unblock", "203.0.113.7")
        self.assertEqual(self.rules(), [(4, mine)])
        self.assertEqual(r.returncode, 3, "the address is still blocked, by your rule")
        self.assertIn("deny from 203.0.113.7", r.stderr)

    def test_block_refuses_when_a_rule_of_yours_matches(self):
        mine = tuple_line("allow any any ::/0 any 2001:db8::7 in")
        self.seed(6, mine)
        r = self.admin("block", "2001:db8::7")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.rules(), [(6, mine)])
        self.assertIn("Nothing was changed", r.stderr)

    def test_a_ufw_that_deletes_the_wrong_duplicate_is_reported(self):
        # If a ufw ignored the comment when deleting, it would take your rule
        # (the first); the helper sees that and says what to put back.
        self.env["FAKE_UFW_DELETE_IGNORES_COMMENT"] = "1"
        mine = tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in")
        self.seed(4, mine, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in", BLOCK))
        r = self.admin("unblock", "203.0.113.7")
        self.assertEqual(r.returncode, 4)
        self.assertIn("removed: " + mine, r.stderr)
        self.assertIn("Put them back", r.stderr)

    def test_a_failing_ufw_is_reported(self):
        self.env["FAKE_UFW_FAIL"] = "1"
        r = self.admin("block", "203.0.113.7")
        self.assertEqual(r.returncode, 1)
        self.assertIn("fake ufw told to fail", r.stderr)

    def test_the_stand_in_deletes_like_ufw_0_36_2(self):
        # What the old helper relied on: a delete without the comment takes
        # your rule too (backend_iptables.py set_rule, the ret == -2 branch).
        self.seed(4, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in"),
                  tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in", BLOCK))
        subprocess.run(["ufw", "delete", "deny", "from", "203.0.113.7"], check=True, capture_output=True,
                       env=dict(self.env, PATH=self.bin + os.pathsep + os.environ["PATH"]))
        self.assertEqual(self.rules(), [])

    def test_the_helper_refuses_anything_odd(self):
        for args in (("lockdown", "sideways"), ("block", "not-an-ip"), ("block",), ("unblock", "1.2.3.4", "x"),
                     ("remove-all", "now"), ("flush",)):
            r = self.admin(*args)
            self.assertEqual(r.returncode, 2, args)
        self.assertEqual(self.ufw_calls(), [])
        env = {k: v for k, v in self.env.items() if k != "FATHOM_SENTINEL_ETC"}
        if os.geteuid() != 0:
            r = self.admin("block", "203.0.113.7", env=env)
            self.assertEqual(r.returncode, 2)
            self.assertIn("run as root", r.stderr)

    # ------------------------------------------------------------ uninstall

    def seed_mixed(self):
        """Fathom's rules next to yours, some the same apart from the comment."""
        self.users_rules()
        mine = [
            (4, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in")),
            (4, tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0", MINE)),
            (6, tuple_line("deny any any ::/0 any ::/0 in_wlan0", MINE)),
        ]
        odd = (4, tuple_line("deny tcp 22 0.0.0.0/0 any 198.51.100.9 in", BLOCK))
        for family, line in mine + [odd]:
            self.seed(family, line)
        self.seed(4, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in", BLOCK),
                  tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_wlan0", LOCK),
                  tuple_line("deny any any 0.0.0.0/0 any 0.0.0.0/0 in_enp3s0", LOCK))
        self.seed(6, tuple_line("deny any any ::/0 any 2001:db8::7 in", BLOCK),
                  tuple_line("deny any any ::/0 any ::/0 in_wlan0", LOCK),
                  tuple_line("deny any any ::/0 any ::/0 in_enp3s0", LOCK))
        return odd

    def test_remove_all_takes_fathoms_rules_and_leaves_yours(self):
        odd = self.seed_mixed()
        r = self.admin("remove-all")
        left = self.rules()
        self.assertFalse([l for _, l in left if l.endswith(LOCK)])
        self.assertEqual([x for x in left if x[1].endswith(BLOCK)], [odd])
        self.assertEqual(len(left), 7, left)
        # The one with Fathom's comment but not its shape may be yours: kept and named.
        self.assertEqual(r.returncode, 3)
        self.assertIn("deny tcp 22", r.stderr)

    def test_uninstall_takes_fathoms_rules_and_leaves_yours(self):
        self.seed_mixed()
        lib = os.path.join(self.root, "usr/local/lib/fathom-sentinel")
        os.makedirs(lib)
        os.makedirs(os.path.join(self.etc, "systemd/system"))
        env = dict(self.env, FATHOM_SENTINEL_ROOT=self.root)
        r = subprocess.run(["bash", INSTALL_ROOT, "uninstall"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 3, r.stderr)
        self.assertIn("some firewall rules were left", r.stderr)
        self.assertFalse(os.path.exists(lib))
        left = self.rules()
        self.assertEqual(len(left), 7, left)
        self.assertIn((4, tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in")), left)
        self.assertIn((6, tuple_line("deny any any ::/0 any ::/0 in_wlan0", MINE)), left)

    def test_uninstall_with_only_fathoms_rules_succeeds(self):
        self.users_rules()
        before = self.rules()
        self.assertEqual(self.admin("lockdown", "on").returncode, 0)
        self.assertEqual(self.admin("block", "203.0.113.7").returncode, 0)
        env = dict(self.env, FATHOM_SENTINEL_ROOT=self.root)
        r = subprocess.run(["bash", INSTALL_ROOT, "uninstall"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.rules(), before)


PULSE = "fathom-pulse".encode().hex()
PULSE_RULE = "allow tcp 4317,4318 172.17.0.1 any 172.16.0.0/12 in"
PULSE_DEPS = subprocess.run(["/usr/bin/python3", "-I", "-c", "import grpc, google.protobuf, opentelemetry.proto"],
                            capture_output=True).returncode == 0


@unittest.skipUnless(PULSE_DEPS, "Pulse's Python packages aren't installed")
class PulseRule(unittest.TestCase):
    """install.sh --pulse adds ufw's rule for containers only when no rule of
    yours matches it, and uninstall.sh removes it by its comment. sudo,
    pkexec and ufw are stand-ins that only record their arguments."""

    def setUp(self):
        from install_env import Sandbox
        self.box = Sandbox()
        self.addCleanup(self.box.cleanup)
        os.makedirs(self.box.env["FATHOM_UFW_DIR"])

    def user_rules(self, *lines):
        with open(os.path.join(self.box.env["FATHOM_UFW_DIR"], "user.rules"), "w") as f:
            f.write("".join("\n" + l + "\n" for l in lines))

    def ufw_calls(self):
        return [c for c in self.box.calls() if c.startswith(("sudo ufw", "pkexec ufw"))]

    def test_no_rule_yet_adds_fathoms_and_a_rerun_adds_nothing(self):
        r = self.box.run("install.sh", "--pulse", STUB_DOCKER0="172.17.0.1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.ufw_calls(), ["pkexec ufw allow proto tcp from 172.16.0.0/12 to 172.17.0.1 "
                                            "port 4317,4318 comment fathom-pulse"])
        self.user_rules(tuple_line(PULSE_RULE, PULSE))
        self.box.clear_calls()
        r = self.box.run("install.sh", "--pulse", STUB_DOCKER0="172.17.0.1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.ufw_calls(), [])
        r = self.box.run("uninstall.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pkexec ufw delete allow proto tcp from 172.16.0.0/12 to 172.17.0.1 port 4317,4318 "
                      "comment fathom-pulse", self.box.calls())

    def test_a_matching_rule_of_yours_is_left_alone(self):
        for mine in (tuple_line(PULSE_RULE, MINE), tuple_line(PULSE_RULE),
                     tuple_line(PULSE_RULE.replace("allow", "deny"), PULSE)):
            self.user_rules(mine)
            self.box.clear_calls()
            r = self.box.run("install.sh", "--pulse", STUB_DOCKER0="172.17.0.1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(self.ufw_calls(), [], mine)
            self.assertIn("a firewall rule of yours", r.stdout)
            self.assertFalse(os.path.exists(self.box.path(".local/state/fathom/pulse-bridge")))


class SentinelStatus(unittest.TestCase):
    """What the deck shows comes from Fathom's rules in both files."""

    def test_ipv6_blocks_and_lockdown_are_read(self):
        loader = importlib.machinery.SourceFileLoader(
            "fathom_sentinel_cli", os.path.join(REPO, "sentinel", "bin", "fathom-sentinel"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cli = importlib.util.module_from_spec(spec)
        loader.exec_module(cli)
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        v4, v6 = os.path.join(tmp, "user.rules"), os.path.join(tmp, "user6.rules")
        with open(v4, "w") as f:
            f.write(tuple_line("deny any any 0.0.0.0/0 any 203.0.113.7 in", BLOCK) + "\n")
        with open(v6, "w") as f:
            f.write(tuple_line("deny any any ::/0 any 2001:db8::7 in", BLOCK) + "\n")
            f.write(tuple_line("deny any any ::/0 any ::/0 in_wlan0", LOCK) + "\n")
        self.assertEqual(cli.fathom_rules((v4, v6)), (True, ["2001:db8::7", "203.0.113.7"]))
        self.assertEqual(cli.fathom_rules((v4,)), (False, ["203.0.113.7"]))


if __name__ == "__main__":
    unittest.main()

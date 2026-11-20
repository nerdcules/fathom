"""fathom-desk, run with stand-ins for hyprctl, nmcli, ip and Omarchy's own
commands: what it reads, that one failing tool doesn't blank the rest, and
that `set` turns things on or off only when they aren't already, and
refuses values it doesn't know."""

import json
import os
import subprocess
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESK = os.path.join(REPO, "desk", "bin", "fathom-desk")


def stub(folder, name, script):
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + script)
    os.chmod(path, 0o755)


HYPRCTL = """case "$1 $2" in
  "clients -j") echo '[{"address":"0xa","workspace":{"id":1,"name":"1"},"focusHistoryID":0}]' ;;
  "workspaces -j") echo '[{"id":1,"windows":1}]' ;;
  "monitors -j") echo '[{"name":"eDP-1","focused":true,"width":2496,"height":1664,"scale":1.0833334,"reserved":[0,39,0,0]}]' ;;
  "activewindow -j") echo '{"address":"0xa"}' ;;
  "getoption general:gaps_in") echo '{"option":"general:gaps_in","css":"5 5 5 5","set":true}' ;;
  "getoption general:gaps_out") echo '{"option":"general:gaps_out","css":"10 10 10 10","set":true}' ;;
  "getoption general:border_size") echo '{"option":"general:border_size","int":2,"set":true}' ;;
esac
"""


# What `ip -j addr show` gives, cut down, with documentation addresses
# (RFC 5737, RFC 3849). test_deck_status.py uses it too.
IP_ADDR = [
    {"ifname": "lo", "operstate": "UNKNOWN", "link_type": "loopback", "addr_info": [
        {"family": "inet", "local": "127.0.0.1", "scope": "host"}]},
    {"ifname": "wlan0", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "192.0.2.10", "scope": "global", "dynamic": True},
        {"family": "inet6", "local": "2001:db8::10", "scope": "global", "dynamic": True},
        {"family": "inet6", "local": "2001:db8::dead", "scope": "global", "deprecated": True},
        {"family": "inet6", "local": "fe80::1", "scope": "link"}]},
    {"ifname": "enp1s0", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "198.51.100.7", "scope": "global"}]},
    {"ifname": "enp2s0", "operstate": "DOWN", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "198.51.100.8", "scope": "global"}]},
    {"ifname": "tailscale0", "operstate": "UNKNOWN", "link_type": "none", "addr_info": [
        {"family": "inet", "local": "100.64.0.5", "scope": "global"},
        {"family": "inet6", "local": "2001:db8:ffff::5", "scope": "global"}]},
    {"ifname": "wg0", "operstate": "UNKNOWN", "link_type": "none", "addr_info": [
        {"family": "inet", "local": "203.0.113.2", "scope": "global"}]},
    {"ifname": "docker0", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "172.17.0.1", "scope": "global"}]},
    {"ifname": "veth1a2b", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "172.17.0.9", "scope": "global"}]},
    {"ifname": "eth9", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet", "local": "$(reboot)", "scope": "global"}]},
    {"ifname": "eth8", "operstate": "UP", "link_type": "ether", "addr_info": [
        {"family": "inet6", "local": "fe80::2", "scope": "link"}]},
]

# What it should make of it: interfaces that are up, global addresses that
# aren't deprecated, no loopback, Docker or veth, nothing that isn't an
# address, and none left with no address.
ADDRESSES = [
    {"name": "wlan0", "kind": "wifi", "ipv4": ["192.0.2.10"], "ipv6": ["2001:db8::10"]},
    {"name": "enp1s0", "kind": "ethernet", "ipv4": ["198.51.100.7"], "ipv6": []},
    {"name": "tailscale0", "kind": "tailscale", "ipv4": ["100.64.0.5"], "ipv6": ["2001:db8:ffff::5"]},
    {"name": "wg0", "kind": "vpn", "ipv4": ["203.0.113.2"], "ipv6": []},
]


def ip_stub(folder, data):
    """A stand-in for ip, and a /sys/class/net where wlan0 is wireless."""
    stub(folder, "ip", "cat <<'EOF'\n" + json.dumps(data) + "\nEOF\n")
    net = os.path.join(os.path.dirname(folder), "net")
    os.makedirs(os.path.join(net, "wlan0", "wireless"), exist_ok=True)
    os.makedirs(os.path.join(net, "enp1s0"), exist_ok=True)
    return net


class DeskTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.dir = self._dir.name
        self.bin = os.path.join(self.dir, "bin")
        os.mkdir(self.bin)
        self.log = os.path.join(self.dir, "calls")
        self.state = os.path.join(self.dir, "state")
        os.makedirs(os.path.join(self.state, "omarchy", "indicators"))
        # Every tool the desk might touch, logging its arguments.
        for name in ["nmcli", "omarchy-shell", "omarchy-toggle-nightlight", "omarchy-toggle-idle",
                     "omarchy-toggle-notification-silencing", "omarchy-brightness-display",
                     "omarchy-powerprofiles-set", "omarchy-powerprofiles-list", "powerprofilesctl", "hyprctl", "ip"]:
            stub(self.bin, name, f'echo "{name} $*" >> "{self.log}"\n')

    def tearDown(self):
        self._dir.cleanup()

    def run_desk(self, *args, env=None):
        e = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"], XDG_STATE_HOME=self.state)
        e.update(env or {})
        return subprocess.run([DESK, *args], capture_output=True, text=True, env=e, timeout=30)

    def calls(self):
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    # ------------------------------------------------ state

    def test_state_and_the_gaps_tiling_leaves(self):
        stub(self.bin, "hyprctl", HYPRCTL)
        out = self.run_desk("state")
        self.assertEqual(out.returncode, 0, out.stderr)
        state = json.loads(out.stdout)
        self.assertEqual(state["clients"][0]["address"], "0xa")
        self.assertEqual(state["active"], {"address": "0xa"})
        # gaps_out 10 + border 2 at the edge; 2 x (gaps_in 5 + border 2) between.
        self.assertEqual((state["gapsOut"], state["gapsIn"]), (12, 14))

    def test_state_when_hyprland_answers_nonsense(self):
        stub(self.bin, "hyprctl", "echo 'not json'\n")
        state = json.loads(self.run_desk("state").stdout)
        self.assertEqual((state["clients"], state["workspaces"], state["monitors"]), ([], [], []))
        self.assertEqual(state["active"], {"address": None})
        self.assertEqual((state["gapsOut"], state["gapsIn"]), (0, 0))

    # ------------------------------------------------ settings

    def settings(self, **env):
        out = self.run_desk("settings", env=env)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_settings_from_each_tool(self):
        stub(self.bin, "nmcli", """case "$*" in
  "-t -f WIFI radio") echo enabled ;;
  *"dev wifi list"*) echo 'no:Other:40'; echo 'yes:Home:72' ;;
esac
""")
        stub(self.bin, "omarchy-shell", 'echo on\n')
        stub(self.bin, "omarchy-toggle-nightlight", '[ "$1" = --status ] && echo \'{"enabled":false,"temperature":6500}\'\n')
        stub(self.bin, "omarchy-brightness-display", 'echo 17\n')
        stub(self.bin, "powerprofilesctl", 'echo balanced\n')
        stub(self.bin, "omarchy-powerprofiles-list", 'printf "power-saver\\nbalanced\\nperformance\\n"\n')
        power = os.path.join(self.dir, "power")
        os.makedirs(os.path.join(power, "BAT1"))
        for name, value in [("capacity", "68"), ("status", "Discharging")]:
            with open(os.path.join(power, "BAT1", name), "w") as f:
                f.write(value + "\n")
        open(os.path.join(self.state, "omarchy", "indicators", "stay-awake"), "w").close()
        s = self.settings(FATHOM_DESK_POWER=power)
        self.assertEqual(s["wifi"], {"on": True, "ssid": "Home", "signal": 72})
        self.assertEqual((s["focus"], s["nightlight"], s["awake"], s["brightness"]), (True, False, True, 17))
        self.assertEqual(s["battery"], {"pct": 68, "status": "Discharging"})
        self.assertEqual(s["profile"], {"current": "balanced", "all": ["power-saver", "balanced", "performance"]})

    def test_settings_when_tools_are_missing_or_odd(self):
        # Every stand-in prints nothing; no battery.
        s = self.settings(FATHOM_DESK_POWER=os.path.join(self.dir, "none"))
        self.assertIsNone(s["wifi"])
        self.assertIsNone(s["focus"])
        self.assertIsNone(s["brightness"])
        self.assertIsNone(s["battery"])
        self.assertIsNone(s["profile"])
        self.assertIsNone(s["addresses"])
        self.assertFalse(s["awake"])

    def test_addresses_from_ip(self):
        net = ip_stub(self.bin, IP_ADDR)
        self.assertEqual(self.settings(FATHOM_NET=net)["addresses"], ADDRESSES)

    def test_addresses_when_ip_says_something_odd(self):
        for out, want in [("not json", None), ('{"ifname":"wlan0"}', None), ("[]", []),
                          ('[1, "x", {"ifname": 3, "addr_info": "no"}]', []), ("[]\n[]", [])]:
            stub(self.bin, "ip", f"cat <<'EOF'\n{out}\nEOF\n")
            self.assertEqual(self.settings()["addresses"], want, out)

    # ------------------------------------------------ set

    def test_set_only_changes_what_differs(self):
        stub(self.bin, "omarchy-shell", f'echo "omarchy-shell $*" >> "{self.log}"; echo on\n')
        self.assertEqual(self.run_desk("set", "focus", "on").returncode, 0)
        self.assertNotIn("omarchy-toggle-notification-silencing", self.calls())
        self.assertEqual(self.run_desk("set", "focus", "off").returncode, 0)
        self.assertIn("omarchy-toggle-notification-silencing ", self.calls())

    def test_stay_awake_follows_omarchys_file(self):
        self.assertEqual(self.run_desk("set", "awake", "off").returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.run_desk("set", "awake", "on").returncode, 0)
        self.assertEqual(self.calls(), ["omarchy-toggle-idle "])

    def test_wifi_profile_and_brightness_reach_their_tools(self):
        for args in [("wifi", "off"), ("profile", "power-saver"), ("brightness", "40")]:
            out = self.run_desk("set", *args)
            self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.calls(), [
            "nmcli radio wifi off",
            "omarchy-powerprofiles-set autodetect power-saver",
            "omarchy-brightness-display --no-osd 40%",
        ])

    def test_set_refuses_what_it_doesnt_know(self):
        for args in [("wifi", "maybe"), ("brightness", "0"), ("brightness", "101"), ("brightness", "4O"),
                     ("brightness", "40; rm -rf ~"), ("profile", "Turbo Mode"), ("profile", "$(id)"),
                     ("volume", "3"), ("focus", "")]:
            out = self.run_desk("set", *args)
            self.assertEqual(out.returncode, 2, args)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()

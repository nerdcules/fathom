# Run with: python3 -m unittest discover -s tests
# Checks what Sentinel makes of journal lines, neighbours and file checks.
# Nothing here reads the real journal, network or disk.

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "sentinel"))

from fathom_sentinel import detect  # noqa: E402

UFW = ("[UFW BLOCK] IN=wlp0s20f3 OUT= MAC=02:00:00:00:00:01:a0:d7 SRC={src} DST=192.168.8.213 "
       "LEN=441 TOS=0x00 PROTO=TCP SPT=42735 DPT={port} WINDOW=1024 SYN")


class Firewall(unittest.TestCase):
    def test_parses_blocks(self):
        b = detect.parse_ufw(UFW.format(src="203.0.113.47", port=22))
        self.assertEqual(b["src"], "203.0.113.47")
        self.assertEqual(b["dport"], "22")
        self.assertEqual(b["proto"], "TCP")
        self.assertTrue(b["inbound"])
        self.assertIsNone(detect.parse_ufw("[UFW ALLOW] SRC=1.2.3.4"))
        self.assertIsNone(detect.parse_ufw("[UFW BLOCK] SRC=<script> DPT=1"))
        self.assertIsNone(detect.parse_ufw(None))

    def test_top_sources_put_the_internet_first(self):
        sources = {"192.168.8.90": 191, "192.168.8.39": 113, "192.168.1.246": 44,
                   "192.168.1.125": 32, "192.168.1.254": 12, "2a06:98c1:3109::6812:2929": 10}
        top = detect.top_sources(sources)
        self.assertEqual([t["src"] for t in top],
                         ["2a06:98c1:3109::6812:2929", "192.168.8.90", "192.168.8.39", "192.168.1.246"])
        self.assertEqual(top[0], {"src": "2a06:98c1:3109::6812:2929", "count": 10, "public": True})
        self.assertEqual(detect.top_sources({}), [])
        self.assertEqual(detect.top_sources({"2a06:98c1:3109:0000:0000:0000:6812:2929": 1})[0]["src"],
                         "2a06:98c1:3109::6812:2929")

    def test_public_or_local(self):
        self.assertTrue(detect.is_public("203.0.113.47") is False)  # documentation range isn't global
        self.assertTrue(detect.is_public("8.8.8.8"))
        self.assertFalse(detect.is_public("192.168.8.90"))
        self.assertFalse(detect.is_public("nonsense"))

    def test_chatter_is_not_a_scan(self):
        d = detect.ScanDetector()
        for i in range(200):
            self.assertIsNone(d.feed(detect.parse_ufw(UFW.format(src="192.168.8.90", port=54889)), 1000 + i))

    def test_many_ports_is_a_scan_reported_once(self):
        d = detect.ScanDetector()
        hits = [d.feed(detect.parse_ufw(UFW.format(src="8.8.8.8", port=1000 + i)), 1000 + i) for i in range(40)]
        found = [h for h in hits if h]
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["level"], "bad")
        self.assertIn("8.8.8.8", found[0]["title"])
        self.assertIn("internet", found[0]["detail"])
        self.assertEqual(found[0]["data"]["src"], "8.8.8.8")

    def test_ports_spread_over_hours_are_not_a_scan(self):
        d = detect.ScanDetector()
        hits = [d.feed(detect.parse_ufw(UFW.format(src="8.8.8.8", port=1000 + i)), i * 600) for i in range(40)]
        self.assertFalse(any(hits))


class SignIns(unittest.TestCase):
    def test_sudo_commands(self):
        a = detect.parse_auth("sudo", "alex : TTY=pts/1 ; PWD=/home/s ; USER=root ; COMMAND=/usr/bin/pacman -Syu")
        self.assertEqual(a, {"type": "sudo", "user": "alex", "command": "/usr/bin/pacman -Syu"})

    def test_sudo_summary_is_not_counted_twice(self):
        self.assertIsNone(detect.parse_auth("sudo", "alex : 3 incorrect password attempts ; TTY=pts/1"))

    def test_pam_failures(self):
        a = detect.parse_auth("sudo", "pam_unix(sudo:auth): authentication failure; logname=s uid=1000 euid=0 tty=/dev/pts/1 ruser=s rhost=  user=s")
        self.assertEqual(a["type"], "fail")
        self.assertEqual(a["service"], "sudo")
        self.assertEqual(a["user"], "s")

    def test_ssh(self):
        a = detect.parse_auth("sshd", "Failed password for invalid user admin from 203.0.113.47 port 52211 ssh2")
        self.assertEqual((a["type"], a["user"], a["from"]), ("fail", "admin", "203.0.113.47"))
        a = detect.parse_auth("sshd", "Accepted publickey for s from 192.168.8.5 port 1 ssh2: ED25519")
        self.assertEqual((a["type"], a["user"], a["from"]), ("login", "s", "192.168.8.5"))

    def test_one_typo_is_info_three_is_a_warning(self):
        d = detect.FailureDetector()
        fail = {"type": "fail", "service": "sudo", "user": "s", "count": 1}
        self.assertEqual(d.feed(fail, 100)["level"], "info")
        self.assertEqual(d.feed(fail, 160)["level"], "info")
        self.assertEqual(d.feed(fail, 220)["level"], "warn")
        # Quiet for a while after warning.
        self.assertEqual(d.feed(fail, 230)["level"], "info")

    def test_typos_far_apart_stay_info(self):
        d = detect.FailureDetector()
        fail = {"type": "fail", "service": "sudo", "count": 1}
        for t in (0, 1000, 2000, 3000):
            self.assertEqual(d.feed(fail, t)["level"], "info")

    def test_remote_failure_is_bad_at_once(self):
        d = detect.FailureDetector()
        e = d.feed({"type": "fail", "service": "ssh", "user": "root", "from": "203.0.113.47", "count": 1}, 5)
        self.assertEqual(e["level"], "bad")
        self.assertEqual(e["data"]["src"], "203.0.113.47")


class Devices(unittest.TestCase):
    INDEX = detect.oui_index([
        "00-1A-2B   (hex)\t\tExample Networks\n",
        "001A2B     (base 16)\t\tExample Networks\n",
        "74-19-F8   (hex)\t\tIEEE Registration Authority\n",
    ])

    def test_vendors(self):
        self.assertEqual(self.INDEX["001A2B"], "Example Networks")
        self.assertEqual(detect.vendor("00:1a:2b:00:00:01", self.INDEX), "Example Networks")
        self.assertEqual(detect.vendor("36:00:00:00:00:83", self.INDEX), "Private address")
        self.assertEqual(detect.vendor("00:11:22:33:44:55", self.INDEX), "")

    def test_neighbours_prefer_ipv4_and_skip_failures(self):
        entries = [
            {"dst": "192.168.8.1", "dev": "wl0", "lladdr": "00:1a:2b:00:00:01", "state": ["REACHABLE"]},
            {"dst": "fd00::1", "dev": "wl0", "lladdr": "00:1a:2b:00:00:01", "state": ["STALE"]},
            {"dst": "192.168.8.9", "dev": "wl0", "state": ["FAILED"]},
            {"dst": "192.168.8.8", "dev": "wl0", "lladdr": "aa:bb:cc:dd:ee:ff", "state": ["FAILED"]},
            {"dst": "10.0.0.2", "dev": "docker0", "lladdr": "02:42:ac:11:00:02", "state": ["REACHABLE"]},
            {"dst": "192.168.8.7", "dev": "wl0", "lladdr": "<bad>", "state": ["REACHABLE"]},
        ]
        self.assertEqual(detect.neighbours(entries, "wl0"), {"00:1a:2b:00:00:01": "192.168.8.1"})

    def test_new_network_learns_quietly_then_reports_newcomers(self):
        w = detect.DeviceWatch()
        self.assertEqual(w.feed("net1", {"00:1a:2b:00:00:01": "192.168.8.1"}, self.INDEX, 1000), [])
        self.assertEqual(w.feed("net1", {"aa:aa:aa:aa:aa:01": "192.168.8.50"}, self.INDEX, 1300), [])
        later = w.feed("net1", {"aa:aa:aa:aa:aa:02": "192.168.8.51"}, self.INDEX, 1000 + detect.DeviceWatch.LEARN + 1)
        self.assertEqual(len(later), 1)
        self.assertEqual(later[0]["kind"], "device")
        self.assertEqual(later[0]["data"]["mac"], "aa:aa:aa:aa:aa:02")
        self.assertIn("Private address", later[0]["detail"])
        # Seen again: nothing new.
        self.assertEqual(w.feed("net1", {"aa:aa:aa:aa:aa:02": "192.168.8.51"}, self.INDEX, 5000), [])
        self.assertTrue(w.networks["net1"]["devices"]["00:1a:2b:00:00:01"]["trusted"])
        self.assertFalse(w.networks["net1"]["devices"]["aa:aa:aa:aa:aa:02"]["trusted"])

    def test_old_devices_are_forgotten(self):
        w = detect.DeviceWatch()
        w.feed("n", {"aa:aa:aa:aa:aa:01": "1.1.1.1"}, {}, 0)
        w.feed("n", {}, {}, 61 * 86400)
        self.assertEqual(w.networks["n"]["devices"], {})


class Files(unittest.TestCase):
    def test_only_new_differences_count(self):
        before = [{"pkg": "a", "path": "/etc/x"}]
        now = [{"pkg": "a", "path": "/etc/x"}, {"pkg": "b", "path": "/usr/bin/y"}]
        self.assertEqual(detect.integrity_changes(before, now), [{"pkg": "b", "path": "/usr/bin/y"}])
        self.assertEqual(detect.integrity_changes(None, []), [])

    CHECKED = {"files": 10, "packages": 2, "alteredCount": 2501,
               "altered": [{"pkg": "a", "path": "/etc/x"}]}

    def test_first_check_with_differences_is_a_baseline_not_a_match(self):
        e = detect.integrity_event(None, self.CHECKED, 100)
        self.assertEqual((e["level"], e["title"]), ("info", "System files: first check done"))
        self.assertIn("2501 of 10 files differ", e["detail"])

    def test_first_check_without_differences_matches(self):
        e = detect.integrity_event(None, {"files": 10, "packages": 2, "altered": []}, 100)
        self.assertEqual(e["title"], "System files match their packages")

    def test_same_differences_again_are_not_new(self):
        e = detect.integrity_event({"altered": self.CHECKED["altered"]}, self.CHECKED, 100)
        self.assertEqual((e["level"], e["title"]), ("info", "No new changes to system files"))

    def test_new_difference_warns(self):
        e = detect.integrity_event({"altered": []}, self.CHECKED, 100)
        self.assertEqual((e["level"], e["title"]), ("warn", "1 system file changed"))
        self.assertIn("/etc/x no longer matches", e["detail"])


class Text(unittest.TestCase):
    def test_event_text_is_one_safe_line(self):
        e = detect.event("x", "info", "a\nb\x00c", "d" * 500)
        self.assertEqual(e["title"], "a b c")
        self.assertEqual(len(e["detail"]), detect.MAX_TEXT)


if __name__ == "__main__":
    unittest.main()

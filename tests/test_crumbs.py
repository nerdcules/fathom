"""fathom-crumbs and its root helper, against made-up browser profiles in a
scratch home: reading Chromium-family and Firefox cookies, classifying them
with an Edge-style tracker list, linking them to the sites that led to
them, the rules the helper writes, and forgetting cookies only in browsers
that aren't running."""

import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRUMBS = os.path.join(REPO, "crumbs", "bin", "fathom-crumbs")
HELPER = os.path.join(REPO, "crumbs", "root", "policy")
EPOCH = 11644473600
NOW = int(time.time())


def chromium_us(t):
    return (t + EPOCH) * 1_000_000


def make_chromium(profile, cookies, visits):
    os.makedirs(profile, exist_ok=True)
    with sqlite3.connect(os.path.join(profile, "Cookies")) as db:
        db.execute("CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, "
                   "top_frame_site_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, "
                   "encrypted_value BLOB NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, "
                   "is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, "
                   "has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, "
                   "samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL, source_port INTEGER NOT NULL, "
                   "last_update_utc INTEGER NOT NULL, source_type INTEGER NOT NULL, "
                   "has_cross_site_ancestor INTEGER NOT NULL)")
        for c in cookies:
            db.execute("INSERT INTO cookies VALUES (?,?,?,?,'',?,?,?,1,0,?,1,?,1,?,2,443,0,0,0)",
                       (chromium_us(c["created"]), c["host"], c.get("top", ""), c["name"],
                        b"v10" + b"x" * 20, "/", chromium_us(c["expires"]) if c.get("expires") else 0,
                        chromium_us(c["created"]), 1 if c.get("expires") else 0, c.get("samesite", 0)))
    with sqlite3.connect(os.path.join(profile, "History")) as db:
        db.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT)")
        db.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)")
        for i, (t, url) in enumerate(visits, 1):
            db.execute("INSERT INTO urls VALUES (?,?)", (i, url))
            db.execute("INSERT INTO visits VALUES (?,?,?)", (i, i, chromium_us(t)))


def make_firefox(profile, cookies, visits):
    os.makedirs(profile, exist_ok=True)
    with sqlite3.connect(os.path.join(profile, "cookies.sqlite")) as db:
        db.execute("CREATE TABLE moz_cookies(id INTEGER PRIMARY KEY, originAttributes TEXT, name TEXT, "
                   "value TEXT, host TEXT, path TEXT, expiry INTEGER, lastAccessed INTEGER, "
                   "creationTime INTEGER, isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER)")
        for c in cookies:
            db.execute("INSERT INTO moz_cookies (originAttributes, name, value, host, path, expiry, lastAccessed, "
                       "creationTime, isSecure, isHttpOnly, sameSite) VALUES (?,?,?,?,'/',?,?,?,1,0,1)",
                       (c.get("origin", ""), c["name"], "abc", c["host"], c.get("expires") or 0,
                        c["created"] * 1_000_000, c["created"] * 1_000_000))
    with sqlite3.connect(os.path.join(profile, "places.sqlite")) as db:
        db.execute("CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT)")
        db.execute("CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER)")
        for i, (t, url) in enumerate(visits, 1):
            db.execute("INSERT INTO moz_places VALUES (?,?)", (i, url))
            db.execute("INSERT INTO moz_historyvisits VALUES (?,?,?)", (i, i, t * 1_000_000))


class CrumbsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        self.cfg = os.path.join(self.home, ".config")
        self.etc = os.path.join(self.tmp, "etc")
        self.prefix = os.path.join(self.tmp, "root")
        # Edge and Chromium "installed" for the helper.
        for p in ("opt/microsoft/msedge", "usr/lib/chromium"):
            os.makedirs(os.path.join(self.prefix, p))
        lists = os.path.join(self.cfg, "microsoft-edge", "Trust Protection Lists", "1.0.0.1", "Mu")
        os.makedirs(lists)
        for name, text in (("Advertising", "doubleclick.net/\ndemdex.net/\n"),
                           ("Analytics", "clarity.ms/\n"), ("Social", "facebook.com/\n"),
                           ("Content", "youtube.com/\nstaging-tracker.msedgedemo.example/\n"),
                           ("Entities", "doubleclick.net^Google\ndemdex.net^Adobe\nclarity.ms^Microsoft\n")):
            with open(os.path.join(lists, name), "w") as f:
                f.write(text)
        edge = os.path.join(self.cfg, "microsoft-edge", "Default")
        make_chromium(edge, [
            # Stored under shop.example: an exact link.
            {"host": ".doubleclick.net", "name": "IDE", "created": NOW - 500, "expires": NOW + 86400 * 400,
             "top": "https://shop.example.co.uk"},
            # Set 2 s after a visit to news.example.com: a likely link.
            {"host": ".clarity.ms", "name": "MUID", "created": NOW - 1000, "expires": NOW + 86400 * 30},
            # Set while visiting its own site: no link.
            {"host": ".news.example.com", "name": "session", "created": NOW - 1001},
            # Set long after any visit: no link.
            {"host": ".demdex.net", "name": "demdex", "created": NOW - 9000, "expires": NOW + 86400 * 100},
        ], [(NOW - 1002, "https://news.example.com/a"), (NOW - 600, "https://shop.example.co.uk/"),
            (NOW - 1001, "chrome-extension://abcdef/page.html")])
        make_firefox(os.path.join(self.home, ".mozilla", "firefox", "x1.default-release"), [
            {"host": ".facebook.com", "name": "_fbp", "created": NOW - 300, "expires": NOW + 86400 * 90,
             "origin": "^partitionKey=(https,blog.example.org)"},
            {"host": "blog.example.org", "name": "theme", "created": NOW - 310, "expires": NOW + 86400},
        ], [(NOW - 310, "https://blog.example.org/")])
        self.calls = os.path.join(self.tmp, "calls")
        self.env = dict(os.environ, HOME=self.home, XDG_CONFIG_HOME=self.cfg,
                        XDG_RUNTIME_DIR=self.tmp, FATHOM_CRUMBS_ETC=self.etc,
                        FATHOM_CRUMBS_PREFIX=self.prefix, FATHOM_CRUMBS_HELPER=HELPER)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def crumbs(self, *args):
        return subprocess.run([CRUMBS, *args], capture_output=True, text=True, env=self.env, timeout=30)

    def status(self):
        r = self.crumbs("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_every_browser_is_read_and_trackers_named(self):
        s = self.status()
        self.assertEqual(sorted(b["name"] for b in s["browsers"]), ["Firefox", "Microsoft Edge"])
        self.assertEqual(s["totals"]["cookies"], 6)
        self.assertEqual(s["trackerList"], {"source": "edge", "version": "1.0.0.1", "domains": 5})
        by = {d["domain"]: d for d in s["domains"]}
        self.assertEqual((by["doubleclick.net"]["category"], by["doubleclick.net"]["company"]), ("Advertising", "Google"))
        self.assertEqual(by["facebook.com"]["category"], "Social")
        self.assertIsNone(by["example.com"]["category"])
        # Worst kinds first: advertising before social before analytics.
        order = [d["domain"] for d in s["domains"]]
        self.assertLess(order.index("doubleclick.net"), order.index("clarity.ms"))
        self.assertLess(order.index("clarity.ms"), order.index("example.com"))
        # Edge's demo entries aren't trackers.
        self.assertNotIn("msedgedemo.example", json.dumps(s))

    def test_links_are_exact_by_partition_or_likely_by_time(self):
        links = {(l["site"], l["domain"]): l["how"] for l in self.status()["links"]}
        self.assertEqual(links, {
            ("example.co.uk", "doubleclick.net"): "partition",
            ("example.com", "clarity.ms"): "time",
            ("example.org", "facebook.com"): "partition",
        })

    def test_a_domains_cookies_say_what_they_are_without_values(self):
        r = self.crumbs("cookies", "clarity.ms")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout)
        self.assertEqual(len(d["cookies"]), 1)
        c = d["cookies"][0]
        self.assertEqual(c["name"], "MUID")
        self.assertIn("Microsoft", c["purpose"])
        self.assertTrue(c["encrypted"])
        self.assertEqual(c["size"], 23)
        self.assertNotIn("value", c)
        self.assertEqual(self.crumbs("cookies", "not a domain").returncode, 1)

    def test_rules_go_to_each_installed_browser_family(self):
        r = self.crumbs("apply", "--third-party", "on", "--prevention", "strict",
                        "--block", "doubleclick.net", "[*.]demdex.net")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.etc, "opt/edge/policies/managed/fathom-crumbs.json")) as f:
            edge = json.load(f)
        with open(os.path.join(self.etc, "chromium/policies/managed/fathom-crumbs.json")) as f:
            chromium = json.load(f)
        self.assertEqual(edge, {"BlockThirdPartyCookies": True, "TrackingPrevention": 3,
                                "CookiesBlockedForUrls": ["[*.]demdex.net", "[*.]doubleclick.net"]})
        self.assertNotIn("TrackingPrevention", chromium)
        self.assertFalse(os.path.exists(os.path.join(self.etc, "opt/chrome")))  # Chrome isn't installed
        s = self.status()
        self.assertEqual(s["rules"], {"thirdParty": True, "prevention": "strict",
                                      "blocked": ["demdex.net", "doubleclick.net"]})
        self.assertTrue({d["domain"]: d for d in s["domains"]}["demdex.net"]["blocked"])

    def test_block_unblock_and_clear_keep_the_other_rules(self):
        self.assertEqual(self.crumbs("apply", "--third-party", "on", "--prevention", "default").returncode, 0)
        self.assertEqual(self.crumbs("block", "clarity.ms", "demdex.net").returncode, 0)
        self.assertEqual(self.crumbs("unblock", "demdex.net").returncode, 0)
        self.assertEqual(self.status()["rules"], {"thirdParty": True, "prevention": None, "blocked": ["clarity.ms"]})
        self.assertEqual(self.crumbs("clear").returncode, 0)
        self.assertEqual(self.status()["rules"], {"thirdParty": False, "prevention": None, "blocked": []})
        self.assertFalse(os.path.exists(os.path.join(self.etc, "chromium/policies/managed/fathom-crumbs.json")))

    def test_allowing_everything_writes_no_rules(self):
        # A policy that "allows" would lock the browser's own setting.
        self.assertEqual(self.crumbs("apply", "--third-party", "off", "--prevention", "default").returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.etc, "opt/edge/policies/managed/fathom-crumbs.json")))

    def test_the_helper_refuses_anything_odd(self):
        env = dict(self.env)
        for args in (["set", "--third-party", "on", "--prevention", "default", "--block", "bad domain"],
                     ["set", "--third-party", "maybe", "--prevention", "default"],
                     ["set", "--third-party", "on"],
                     ["set", "--third-party", "on", "--prevention", "default", "--block", "a.com", "--x"],
                     ["rm", "-rf"], []):
            r = subprocess.run([HELPER, *args], capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 2, args)
        self.assertFalse(os.path.exists(self.etc))
        for bad in ("bad domain", "a..b", "-a.com", "a.com/x"):
            r = self.crumbs("block", bad)
            self.assertEqual(r.returncode, 1, bad)

    def test_forget_only_where_the_browser_is_closed(self):
        r = self.crumbs("forget", "clarity.ms")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("deleted 1 cookie", r.stdout)
        self.assertNotIn("clarity.ms", [d["domain"] for d in self.status()["domains"]])
        # Edge "running": SingletonLock names this test's own process.
        os.symlink(f"host-{os.getpid()}", os.path.join(self.cfg, "microsoft-edge", "SingletonLock"))
        r = self.crumbs("forget", "doubleclick.net")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Microsoft Edge is running", r.stderr)
        self.assertIn("doubleclick.net", [d["domain"] for d in self.status()["domains"]])

    def test_status_never_changes_the_browsers_files(self):
        path = os.path.join(self.cfg, "microsoft-edge", "Default", "Cookies")
        before = (os.path.getmtime(path), os.path.getsize(path))
        self.status()
        self.crumbs("cookies", "doubleclick.net")
        self.assertEqual((os.path.getmtime(path), os.path.getsize(path)), before)
        self.assertEqual([n for n in os.listdir(self.tmp) if n.startswith("fathom-crumbs.")], [])


if __name__ == "__main__":
    unittest.main()

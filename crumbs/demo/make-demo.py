#!/usr/bin/env python3
"""Made-up browsing for Crumbs' README picture: invented .example sites (a
name reserved for examples) and well-known tracker domains, in a scratch
home with an Edge, a Chromium and a Firefox profile. Runs the real
fathom-crumbs on them, with a few rules set by the real helper into a
scratch /etc, and writes its output to the folder given:

  make-demo.py <out dir>     -> status.json, detail.json (doubleclick.net)

Nothing here reads or touches this machine's browsers.
"""

import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CRUMBS = os.path.join(HERE, "..", "bin", "fathom-crumbs")
HELPER = os.path.join(HERE, "..", "root", "policy")
EPOCH = 11644473600
NOW = int(time.time())
DAY = 86400

SITES = ["dailynews.example", "recipes.example", "shop.example", "travel.example",
         "forum.example", "video.example", "weather.example"]

# (browser, tracker host, cookie name, site it came from, how, days ago, days to live)
# how: "partition" is stored under the site; "time" is set seconds after a visit.
TRACKING = [
    ("edge", ".doubleclick.net", "IDE", "dailynews.example", "time", 3, 390),
    ("edge", ".doubleclick.net", "DSID", "recipes.example", "time", 6, 14),
    ("edge", ".doubleclick.net", "test_cookie", "shop.example", "partition", 0, 0.1),
    ("edge", ".facebook.com", "fr", "recipes.example", "partition", 2, 90),
    ("edge", ".facebook.com", "fr", "shop.example", "partition", 4, 90),
    ("edge", ".clarity.ms", "MUID", "travel.example", "time", 8, 390),
    ("edge", ".criteo.com", "uid", "shop.example", "time", 5, 395),
    ("edge", ".criteo.com", "uid", "travel.example", "partition", 9, 395),
    ("edge", ".taboola.com", "t_gid", "dailynews.example", "partition", 2, 365),
    ("edge", ".taboola.com", "t_pt_gid", "weather.example", "partition", 7, 365),
    ("edge", ".scorecardresearch.com", "UID", "dailynews.example", "time", 10, 395),
    ("edge", ".demdex.net", "demdex", "travel.example", "time", 12, 180),
    ("edge", ".adnxs.com", "uuid2", "forum.example", "partition", 3, 90),
    ("edge", ".hotjar.com", "_hjid", "shop.example", "time", 11, 365),
    ("chromium", ".doubleclick.net", "IDE", "video.example", "partition", 1, 390),
    ("chromium", ".googlesyndication.com", "__gpi", "forum.example", "time", 4, 390),
    ("firefox", ".facebook.com", "fr", "forum.example", "partition", 2, 90),
    ("firefox", ".taboola.com", "t_gid", "weather.example", "partition", 5, 365),
]

# The sites' own cookies: first-party, so no lines on the map.
OWN = [
    ("edge", "dailynews.example", ["_ga", "_ga_K2X7", "session", "consent"]),
    ("edge", "recipes.example", ["_ga", "_fbp", "saved_recipes"]),
    ("edge", "shop.example", ["cart", "_ga", "_fbp", "_hjSessionUser_31", "OptanonConsent"]),
    ("edge", "travel.example", ["search", "currency", "_uetvid"]),
    ("edge", "weather.example", ["units", "place"]),
    ("chromium", "video.example", ["VISITOR_INFO1_LIVE", "YSC", "prefs"]),
    ("chromium", "forum.example", ["session", "theme"]),
    ("firefox", "forum.example", ["session", "theme"]),
    ("firefox", "weather.example", ["units"]),
]


def us(t):
    return int((t + EPOCH) * 1_000_000)


def chromium_profile(folder, cookies, visits):
    os.makedirs(folder)
    with sqlite3.connect(os.path.join(folder, "Cookies")) as db:
        db.execute("CREATE TABLE cookies(creation_utc INTEGER, host_key TEXT, top_frame_site_key TEXT, "
                   "name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, "
                   "is_secure INTEGER, is_httponly INTEGER, last_access_utc INTEGER, has_expires INTEGER, "
                   "is_persistent INTEGER, priority INTEGER, samesite INTEGER, source_scheme INTEGER, "
                   "source_port INTEGER, last_update_utc INTEGER, source_type INTEGER, "
                   "has_cross_site_ancestor INTEGER)")
        for host, name, created, expires, top, secure, samesite in cookies:
            db.execute("INSERT INTO cookies VALUES (?,?,?,?,'',?,'/',?,?,0,?,1,?,1,?,2,443,0,0,0)",
                       (us(created), host, top, name, b"v11" + b"\0" * (19 + len(name) * 3),
                        us(expires) if expires else 0, secure, us(created + 60),
                        1 if expires else 0, samesite))
    with sqlite3.connect(os.path.join(folder, "History")) as db:
        db.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT)")
        db.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)")
        for i, (t, site) in enumerate(visits, 1):
            db.execute("INSERT INTO urls VALUES (?,?)", (i, f"https://{site}/"))
            db.execute("INSERT INTO visits VALUES (?,?,?)", (i, i, us(t)))


def firefox_profile(folder, cookies, visits):
    os.makedirs(folder)
    with sqlite3.connect(os.path.join(folder, "cookies.sqlite")) as db:
        db.execute("CREATE TABLE moz_cookies(id INTEGER PRIMARY KEY, originAttributes TEXT, name TEXT, "
                   "value TEXT, host TEXT, path TEXT, expiry INTEGER, lastAccessed INTEGER, "
                   "creationTime INTEGER, isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER)")
        for host, name, created, expires, top, secure, samesite in cookies:
            origin = f"^partitionKey=(https,{top.split('://')[1]})" if top else ""
            db.execute("INSERT INTO moz_cookies (originAttributes, name, value, host, path, expiry, "
                       "lastAccessed, creationTime, isSecure, isHttpOnly, sameSite) "
                       "VALUES (?,?,?,?,'/',?,?,?,?,0,?)",
                       (origin, name, "x" * 24, host, int(expires or 0), (created + 60) * 1_000_000,
                        created * 1_000_000, secure, samesite))
    with sqlite3.connect(os.path.join(folder, "places.sqlite")) as db:
        db.execute("CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT)")
        db.execute("CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER)")
        for i, (t, site) in enumerate(visits, 1):
            db.execute("INSERT INTO moz_places VALUES (?,?)", (i, f"https://{site}/"))
            db.execute("INSERT INTO moz_historyvisits VALUES (?,?,?)", (i, i, t * 1_000_000))


def main(out):
    tmp = tempfile.mkdtemp(prefix="crumbs-demo.")
    try:
        home = os.path.join(tmp, "home")
        cfg = os.path.join(home, ".config")
        jar = {"edge": [], "chromium": [], "firefox": []}
        seen = {"edge": [], "chromium": [], "firefox": []}
        for i, (browser, host, name, site, how, ago, life) in enumerate(TRACKING):
            # Spread visits out so each tracker's moment is its own.
            visit = NOW - int(ago * DAY) - i * 600
            seen[browser].append((visit, site))
            created = visit + 2
            top = f"https://{site}" if how == "partition" else ""
            jar[browser].append((host, name, created, created + life * DAY if life else None, top, 1, 0))
        for j, (browser, site, names) in enumerate(OWN):
            visit = NOW - (j + 1) * 7200
            seen[browser].append((visit, site))
            for name in names:
                jar[browser].append(("." + site, name, visit + 1, visit + 180 * DAY, "", 1, 1))
        chromium_profile(os.path.join(cfg, "microsoft-edge", "Default"), jar["edge"], seen["edge"])
        chromium_profile(os.path.join(cfg, "chromium", "Default"), jar["chromium"], seen["chromium"])
        firefox_profile(os.path.join(home, ".mozilla", "firefox", "demo1.default-release"),
                        jar["firefox"], seen["firefox"])
        # Edge is open: its lock names this script, which is running.
        os.symlink(f"demo-{os.getpid()}", os.path.join(cfg, "microsoft-edge", "SingletonLock"))

        prefix = os.path.join(tmp, "root")
        for p in ("opt/microsoft/msedge", "usr/lib/chromium"):
            os.makedirs(os.path.join(prefix, p))
        env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=cfg, XDG_RUNTIME_DIR=tmp,
                   FATHOM_CRUMBS_ETC=os.path.join(tmp, "etc"), FATHOM_CRUMBS_PREFIX=prefix,
                   FATHOM_CRUMBS_HELPER=HELPER)

        def crumbs(*args):
            return subprocess.run([CRUMBS, *args], env=env, capture_output=True, text=True, check=True).stdout

        crumbs("apply", "--third-party", "off", "--prevention", "balanced", "--block", "doubleclick.net", "taboola.com")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "status.json"), "w") as f:
            f.write(crumbs("status"))
        with open(os.path.join(out, "detail.json"), "w") as f:
            f.write(crumbs("cookies", "doubleclick.net"))
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip())
    main(sys.argv[1])

"""Phone health on the laptop (fathom-phone): samples kept and checked,
the summary the phone's Health screen shows, and the rules' findings. All
from made-up samples; no phone needed."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHONE = os.path.join(REPO, "phone", "bin", "fathom-phone")

NOW = 1_795_000_000
HOUR = 3600


def load():
    loader = importlib.machinery.SourceFileLoader("fathom_phone", PHONE)
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("fathom_phone", loader))
    loader.exec_module(mod)
    return mod


def week(rate_before, rate_today, bg_app_ms=0):
    """Samples every 15 minutes for 7 days on battery: the six days before at
    rate_before % an hour, the last day at rate_today, recharging to 100 at
    the start of each day. bg_app_ms: Maps' background time per sample today."""
    out = []
    for i in range(7 * 96):
        t = NOW - 7 * 86400 + i * 900
        today = t >= NOW - 86400
        rate = rate_today if today else rate_before
        into_day = (i % 96) * 0.25
        level = max(0, round(100 - rate * into_day))
        apps = [{"pkg": "com.android.chrome", "label": "Chrome", "fg": 300000, "bg": 0}]
        if today and bg_app_ms:
            apps.append({"pkg": "com.google.android.apps.maps", "label": "Maps", "fg": 0, "bg": bg_app_ms})
        out.append({"t": t, "level": level, "charging": False, "tempC": 31.5, "thermal": 0, "storagePct": 61, "apps": apps})
    return out


class HealthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load()

    def test_samples_are_checked(self):
        c = self.m.clean_sample
        self.assertIsNone(c({"t": NOW, "level": 101}, NOW))
        self.assertIsNone(c({"t": NOW - 50 * 86400, "level": 50}, NOW))
        self.assertIsNone(c("nope", NOW))
        x = c({"t": NOW, "level": 50, "tempC": 300, "thermal": 9, "storagePct": 61,
               "apps": [{"pkg": "bad pkg!", "fg": 5}, {"pkg": "a.b", "label": "A", "fg": 1000, "bg": 0},
                        {"pkg": "c.d", "fg": 0, "bg": 0}]}, NOW)
        self.assertEqual((x["tempC"], x["thermal"], x["storagePct"]), (None, None, 61))
        self.assertEqual([a["pkg"] for a in x["apps"]], ["a.b"])  # the bad name and the idle app are dropped

    def test_drain_counts_only_time_on_battery(self):
        s = [{"t": 0, "level": 80, "charging": False}, {"t": 1800, "level": 79, "charging": False},
             {"t": 3600, "level": 85, "charging": True}, {"t": 9000, "level": 84, "charging": False}]
        rate, hours = self.m.drain(s, 0, 10000)
        self.assertEqual((rate, hours), (2.0, 0.5))  # charging and the 90-minute gap don't count

    def test_faster_drain_is_found_and_names_the_background_app(self):
        found = self.m.health_findings(week(2.6, 4.1, bg_app_ms=4 * 60000), NOW)
        [f] = found
        self.assertEqual(f["title"], "Battery is draining faster than usual")
        self.assertIn("against your usual 2.6%", f["detail"])
        self.assertIn("Maps ran 6 h 24 min in the background", f["detail"])

    def test_usual_drain_finds_nothing(self):
        self.assertEqual(self.m.health_findings(week(2.6, 2.8), NOW), [])

    def test_too_little_history_says_so_and_finds_nothing(self):
        s = [x for x in week(2.6, 4.1) if x["t"] >= NOW - 86400 - 4 * HOUR]
        self.assertEqual(self.m.health_findings(s, NOW), [])
        self.assertIn("Still learning", self.m.health_summary(s, NOW)["learning"])

    def test_heat_and_storage(self):
        s = week(2.6, 2.6)
        for i, x in enumerate(s[-40:]):
            x["thermal"] = 2 if i % 10 == 0 else 0  # 4 times up to moderate
        s[-1]["storagePct"] = 93
        titles = [f["title"] for f in self.m.health_findings(s, NOW)]
        self.assertEqual(titles, ["The phone slowed itself down for heat 4 times in the last day", "Phone storage is 93% full"])

    def test_summary_for_the_screen(self):
        s = week(2.6, 2.6, bg_app_ms=60000)
        today = self.m.health_summary(s, NOW, "today")
        self.assertEqual(len(today["bars"]), 24)
        self.assertEqual((today["tempC"], today["storagePct"]), (31.5, 61))
        self.assertEqual(today["apps"][0]["label"], "Chrome")
        self.assertTrue(today["apps"][-1]["background"])
        self.assertIsNone(today["learning"])
        wk = self.m.health_summary(s, NOW, "week")
        self.assertEqual(len(wk["bars"]), 7)

    def test_kept_privately_deduplicated_and_pruned(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.m.HEALTH_DIR = tmp
            old = {"t": NOW - 36 * 86400, "level": 50}
            self.assertEqual(self.m.health_add("0123abcd", [old], now=NOW - 36 * 86400 + 60), 1)
            self.assertEqual(self.m.health_add("0123abcd", [{"t": NOW, "level": 40}, {"t": NOW, "level": 40}, {"x": 1}], now=NOW), 2)
            kept = self.m.health_load("0123abcd")
            self.assertEqual([x["t"] for x in kept], [NOW])  # the 36-day-old one is gone, the repeat kept once
            self.assertEqual(os.stat(self.m.health_path("0123abcd")).st_mode & 0o777, 0o600)
            self.m.health_forget("0123abcd")
            self.assertEqual(self.m.health_load("0123abcd"), [])
            with self.assertRaises(self.m.PhoneError):
                self.m.health_path("../etc")


    def test_twenty_questions_a_day(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.m.ASK_DIR = tmp
            self.m.HEALTH_DIR = tmp
            os.environ["FATHOM_CLAUDE"] = "/bin/true"
            try:
                import time as t
                now = int(t.time())
                self.m.write_private(self.m.ask_path("0123abcd"), {"status": "done", "asked": [now - 60] * 20})
                code, reply = self.m.ask_start({"id": "0123abcd", "name": "Pixel"}, None)
                self.assertEqual(code, 429)
                # A day later the count starts again (the stand-in claude says nothing; that's a failed answer, not a refusal).
                self.m.write_private(self.m.ask_path("0123abcd"), {"status": "done", "asked": [now - 90000] * 20})
                self.assertEqual(self.m.ask_start({"id": "0123abcd", "name": "Pixel"}, None)[0], 202)
            finally:
                del os.environ["FATHOM_CLAUDE"]


    def test_answers_read_as_plain_text(self):
        md = "Nothing looks off.\n\n- **Storage:** 53% used.\n- **Heat:**  none\n\n## Next\nAsk again   tomorrow."
        self.assertEqual(self.m.plain_answer(md),
                         "Nothing looks off.\n\n• Storage: 53% used.\n• Heat: none\n\nNext\nAsk again tomorrow.")


    def test_targeted_question_carries_only_the_findings_evidence(self):
        import json as j
        with tempfile.TemporaryDirectory() as tmp:
            self.m.HEALTH_DIR = tmp
            self.m.health_add("0123abcd", week(2.6, 4.1, bg_app_ms=4 * 60000), now=NOW)
            dev = {"id": "0123abcd", "name": "Pixel 8 Pro"}
            title, system, q = self.m.ask_question(dev, "battery-drain", now=NOW, style="targeted")
            self.assertEqual((title, system), ("Battery is draining faster than usual", self.m.ASK_TARGETED))
            self.assertIn("Usual causes to choose from:", q)
            ev = j.loads(q.split("\n")[-1])
            self.assertEqual((ev["drainPctPerHourUsual"], ev["drainPctPerHourLastDay"]), (2.6, 4.1))
            self.assertEqual(ev["appsMostChanged"][0], {"app": "Maps", "backgroundMinLastDay": 384, "backgroundMinUsualDay": 0,
                                                         "screenMinLastDay": 0, "screenMinUsualDay": 0})
            self.assertNotIn('"bars"', q)  # not the whole summary
            # The broad style, and a question with no finding, get the whole summary.
            self.assertIn('"bars"', self.m.ask_question(dev, "battery-drain", now=NOW, style="broad")[2])
            self.assertEqual(self.m.ask_question(dev, None, now=NOW, style="targeted")[1], self.m.ASK_SYSTEM)


if __name__ == "__main__":
    unittest.main()

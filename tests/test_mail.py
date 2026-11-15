# Run with: python3 -m unittest discover -s tests
# Checks Fathom Mail's handling of what mail services send: untrusted text,
# links, which messages count as new, and how they're announced. Nothing
# here talks to a real mail service, the keyring or the desktop.

import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "mail"))

from fathom_mail import core, outlook  # noqa: E402


class Text(unittest.TestCase):
    def test_plain_makes_one_safe_line(self):
        self.assertEqual(core.plain("a\x00b\nc d\x9fe"), "a b c d e")
        self.assertEqual(core.plain(None), "")
        self.assertEqual(len(core.plain("x" * 500, 100)), 100)
        self.assertTrue(core.plain("x" * 500, 100).endswith("…"))

    def test_markup_becomes_literal(self):
        out = core.escape_markup('<img src="https://example.invalid/t">Tom & <b>Jerry</b>')
        self.assertNotIn("<", out)
        self.assertNotIn(">", out)
        self.assertEqual(out, '&lt;img src="https://example.invalid/t"&gt;Tom &amp; &lt;b&gt;Jerry&lt;/b&gt;')

    def test_links_only_to_the_mail_service(self):
        hosts = outlook.LINK_HOSTS
        good = "https://outlook.live.com/owa/?ItemID=abc&exvsurl=1"
        self.assertEqual(core.safe_link(good, hosts), good)
        for bad in ["http://outlook.live.com/x", "https://evil.example/outlook.live.com",
                    "https://outlook.live.com.evil.example/", "javascript:alert(1)", "",
                    None, "https://outlook.live.com/" + "x" * 3000, "file:///etc/passwd"]:
            self.assertIsNone(core.safe_link(bad, hosts), bad)


class Announce(unittest.TestCase):
    def message(self, n, **kw):
        m = {"sender": f"Sender {n}", "subject": f"Subject {n}", "preview": "", "received": n, "link": None}
        m.update(kw)
        return m

    def test_a_few_messages_each_get_one(self):
        with mock.patch.object(core, "notify") as notify:
            core.announce("Outlook", [self.message(1), self.message(2)], "https://outlook.live.com/mail/0/inbox")
        self.assertEqual(notify.call_count, 2)
        headline, body = notify.call_args_list[0].args
        self.assertEqual(headline, "Sender 1")
        self.assertEqual(body, "Subject 1")
        self.assertEqual(notify.call_args_list[0].kwargs["open_argv"], ["xdg-open", "https://outlook.live.com/mail/0/inbox"])

    def test_many_become_one_summary(self):
        with mock.patch.object(core, "notify") as notify:
            core.announce("Outlook", [self.message(i, sender="Same" if i < 3 else f"S{i}") for i in range(8)], None)
        notify.assert_called_once()
        headline, body = notify.call_args.args
        self.assertEqual(headline, "8 new emails")
        self.assertIn("Same", body)
        self.assertEqual(body.count("Same"), 1)
        self.assertIn("more", body)
        self.assertIsNone(notify.call_args.kwargs["open_argv"])

    def test_untrusted_subjects_are_escaped_and_sender_kept_plain(self):
        with mock.patch.object(core, "notify") as notify:
            core.announce("Outlook", [self.message(1, sender="--hint=x <b>", subject="<a href='x'>win</a> & more",
                                                   preview="line\nbreak")], None)
        headline, body = notify.call_args.args
        self.assertEqual(headline, "--hint=x <b>")  # summary is shown as plain text, so left alone
        self.assertEqual(body, "&lt;a href='x'&gt;win&lt;/a&gt; &amp; more\nline break")

    def test_notify_keeps_text_as_dbus_values(self):
        with mock.patch.object(core.subprocess, "run") as run:
            core.notify("--hint=evil", "-rf body", open_argv=["xdg-open", "https://outlook.live.com/x"])
        argv = run.call_args.args[0]
        self.assertEqual(argv[:4], ["busctl", "--user", "--", "call"])
        i = argv.index("susssasa{sv}i")
        self.assertEqual(argv[i + 4], "--hint=evil")
        self.assertEqual(argv[i + 5], "-rf body")
        self.assertIn("omarchy-exec-argv", argv)
        self.assertEqual(argv[argv.index("omarchy-exec-argv") + 2], '["xdg-open", "https://outlook.live.com/x"]')


def graph_message(mid, received, **kw):
    m = {"id": mid, "subject": f"Subject {mid}", "receivedDateTime": received, "isRead": False,
         "bodyPreview": "", "webLink": f"https://outlook.live.com/owa/?ItemID={mid}",
         "inferenceClassification": "focused",
         "from": {"emailAddress": {"name": f"Name {mid}", "address": f"{mid}@example.com"}}}
    m.update(kw)
    return m


class OutlookPoll(unittest.TestCase):
    def provider(self, messages, unread=3):
        p = outlook.Outlook({"id": "outlook", "provider": "outlook", "clientId": "x"})

        def get(url):
            if "/messages?" in url:
                return {"value": messages}
            return {"unreadItemCount": unread}

        p._get = get
        return p

    def test_first_poll_only_sets_the_cursor(self):
        p = self.provider([graph_message("a", "2026-11-15T09:00:00Z")])
        new, unread, cursor = p.poll({})
        self.assertEqual(new, [])
        self.assertEqual(unread, 3)
        self.assertGreater(cursor["since"], 0)

    def test_new_unread_focused_mail_is_reported_once_oldest_first(self):
        msgs = [
            graph_message("c", "2026-11-15T09:05:00Z"),
            graph_message("b", "2026-11-15T09:03:00Z", isRead=True),
            graph_message("o", "2026-11-15T09:02:00Z", inferenceClassification="other"),
            graph_message("a", "2026-11-15T09:01:00Z", webLink="https://evil.example/x"),
        ]
        p = self.provider(msgs)
        new, _, cursor = p.poll({"since": 1, "seen": []})
        self.assertEqual([m["id"] for m in new], ["a", "c"])
        self.assertIsNone(new[0]["link"])
        self.assertEqual(new[1]["link"], "https://outlook.live.com/owa/?ItemID=c")
        self.assertEqual(cursor["since"], outlook._epoch("2026-11-15T09:05:00Z"))

        again, _, _ = p.poll(cursor)
        self.assertEqual(again, [])

    def test_other_inbox_is_included_when_asked(self):
        p = self.provider([graph_message("o", "2026-11-15T09:02:00Z", inferenceClassification="other")])
        new, _, _ = p.poll({"since": 1, "seen": []}, focused_only=False)
        self.assertEqual([m["id"] for m in new], ["o"])

    def test_missing_fields_do_not_break_it(self):
        p = self.provider([{"id": "z"}, {"subject": "no id"}, "junk"])
        new, _, _ = p.poll({"since": 1, "seen": []})
        self.assertEqual(len(new), 1)
        self.assertEqual(new[0]["sender"], "")


class SignedOut(unittest.TestCase):
    def test_tells_you_once_then_waits(self):
        import importlib.machinery
        import importlib.util
        path = os.path.join(os.path.dirname(__file__), "..", "mail", "bin", "fathom-mail")
        loader = importlib.machinery.SourceFileLoader("fathom_mail_cli", path)
        spec = importlib.util.spec_from_loader("fathom_mail_cli", loader)
        cli = importlib.util.module_from_spec(spec)
        loader.exec_module(cli)

        class Gone:
            label = "x"
            inbox_link = None

            def poll(self, cursor, focused_only=True):
                raise core.SignedOut("Microsoft wants you to sign in again")

        config = {"accounts": [{"id": "outlook", "provider": "outlook", "email": "me@example.com"}]}
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(core, "STATE_FILE", os.path.join(tmp, "mail.json")), \
                mock.patch.object(core, "notify") as notify:
            state = {}
            self.assertFalse(cli.check_once(state, {"outlook": Gone()}, config))
            self.assertFalse(cli.check_once(state, {"outlook": Gone()}, config))
            self.assertEqual(notify.call_count, 1)
            self.assertFalse(state["accounts"][0]["signedIn"])
            self.assertEqual(os.stat(core.STATE_FILE).st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()

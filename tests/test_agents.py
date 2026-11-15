"""Pulse's agents timeline, from made-up Claude Code session files."""

import datetime
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "pulse"))

from fathom_pulse import agents  # noqa: E402

DAY = 1_794_700_800          # 2026-11-15 00:00 UTC
SECRET = "my prompt text that must never be kept"


def setUpModule():
    os.environ["TZ"] = "UTC"
    time.tzset()


def stamp(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def prompt(t, cwd, text=SECRET, **kw):
    return {"type": "user", "timestamp": stamp(t), "cwd": cwd, "gitBranch": "main",
            "message": {"role": "user", "content": text}, **kw}


def result(t, cwd):
    return {"type": "user", "timestamp": stamp(t), "cwd": cwd,
            "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"}]}}


def reply(t, cwd, mid, out=10, stop="tool_use", tools=(), **kw):
    content = [{"type": "tool_use", "id": f"{mid}-{i}", "name": name, "input": args}
               for i, (name, args) in enumerate(tools)] or [{"type": "text", "text": "done"}]
    return {"type": "assistant", "timestamp": stamp(t), "cwd": cwd,
            "message": {"id": mid, "model": "claude-test", "stop_reason": stop, "content": content,
                        "usage": {"output_tokens": out}}, **kw}


class Fixture(unittest.TestCase):
    """Made-up Claude Code folders; no tests of its own."""

    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._dir.name, "claude")
        self.repo_a = os.path.join(self._dir.name, "work", "shop")
        self.repo_b = os.path.join(self._dir.name, "work", "lab")
        self.plain = os.path.join(self._dir.name, "notes")
        for folder in (self.repo_a, self.repo_b):
            os.makedirs(os.path.join(folder, ".git"))
        os.makedirs(os.path.join(self.repo_a, "src", "api"))
        os.makedirs(self.plain)
        os.makedirs(os.path.join(self.root, "projects", "p"))
        self.index = agents.Index()

    def tearDown(self):
        self._dir.cleanup()

    def write(self, records, name="s1", raw_tail=b""):
        path = os.path.join(self.root, "projects", "p", name + ".jsonl")
        with open(path, "ab") as f:
            for r in records:
                f.write(json.dumps(r).encode() + b"\n")
            f.write(raw_tail)
        return path

    def today(self, now):
        self.index.scan(self.root, now)
        return {p["name"]: p for p in self.index.today(now, DAY)}


class Agents(Fixture):
    # ----- states

    def test_working_then_waiting_then_working(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 10, self.repo_a, "m1", tools=[("Read", {})]),
                    result(t + 20, self.repo_a), reply(t + 30, self.repo_a, "m2", stop="end_turn"),
                    prompt(t + 90, self.repo_a), reply(t + 100, self.repo_a, "m3", stop="end_turn")])
        shop = self.today(t + 100)["shop"]
        self.assertEqual(shop["spans"], [[t, t + 30, "working"], [t + 30, t + 90, "waiting"], [t + 90, t + 100, "working"]])
        self.assertEqual((shop["working"], shop["waiting"], shop["prompts"]), (40, 60, 2))
        self.assertEqual(shop["state"], "waiting")

    def test_a_long_silence_is_idle(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", stop="end_turn"),
                    prompt(t + 3600, self.repo_a)])
        shop = self.today(t + 3610)["shop"]
        self.assertEqual(shop["spans"], [[t, t + 20, "working"], [t + 20, t + 20 + agents.IDLE_AFTER, "waiting"],
                                         [t + 3600, t + 3610, "working"]])
        # Hours later, with nothing new, it's idle.
        self.assertEqual(self.today(t + 3600 + 5000)["shop"]["state"], "idle")

    def test_interrupted_and_errors_end_a_turn(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), prompt(t + 5, self.repo_a, "[Request interrupted by user]"),
                    prompt(t + 50, self.repo_a), reply(t + 60, self.repo_a, "m1", stop=None, isApiErrorMessage=True)])
        shop = self.today(t + 70)["shop"]
        self.assertEqual(shop["spans"], [[t, t + 5, "working"], [t + 5, t + 50, "waiting"],
                                         [t + 50, t + 60, "working"], [t + 60, t + 70, "waiting"]])
        self.assertEqual(shop["prompts"], 2)

    def test_what_isnt_a_prompt(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a, "<command-name>/model</command-name>"),
                    prompt(t + 1, self.repo_a, "context", isMeta=True),
                    prompt(t + 2, self.repo_a, "summary", isCompactSummary=True),
                    prompt(t + 3, self.repo_a, "<bash-input>ls</bash-input>"),
                    prompt(t + 10, self.repo_a, "<task-notification>done</task-notification>"),
                    reply(t + 20, self.repo_a, "m1", stop="end_turn"),
                    prompt(t + 25, self.repo_a, "sub", isSidechain=True)])
        shop = self.today(t + 30)["shop"]
        self.assertEqual(shop["prompts"], 0)
        # The background task's notice set Claude working; the rest changed nothing.
        self.assertEqual(shop["spans"], [[t + 10, t + 20, "working"], [t + 20, t + 30, "waiting"]])

    def test_two_sessions_at_once_arent_counted_twice(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 100, self.repo_a, "m1", stop="end_turn")], "s1")
        self.write([prompt(t + 50, self.repo_a), reply(t + 200, self.repo_a, "m2", stop="end_turn")], "s2")
        shop = self.today(t + 200)["shop"]
        # Working wins where they overlap.
        self.assertEqual(shop["spans"], [[t, t + 200, "working"]])
        self.assertEqual((shop["working"], shop["waiting"]), (200, 0))
        self.assertEqual(len(shop["sessions"]), 2)

    def test_working_wins_where_sessions_overlap_in_either_order(self):
        a, b = (0, 100, "working"), (50, 200, "waiting")
        for spans in ([a, b], [b, a]):
            self.assertEqual(agents._merge(list(spans)), [[0, 100, "working"], [100, 200, "waiting"]])

    def test_only_today(self):
        t = DAY - 300
        self.write([prompt(t, self.repo_a), reply(t + 600, self.repo_a, "m1", stop="end_turn")])
        shop = self.today(DAY + 300)["shop"]
        self.assertEqual(shop["spans"], [[DAY, DAY + 300, "working"]])
        self.assertEqual(shop["prompts"], 0)       # the prompt was yesterday

    # ----- projects

    def test_a_session_that_moves_between_folders(self):
        t = DAY + 3600
        self.write([prompt(t, os.path.join(self.repo_a, "src", "api")),
                    reply(t + 10, self.plain, "m1", tools=[("Bash", {"command": "ls"})]),
                    result(t + 20, self.repo_b),
                    reply(t + 30, self.repo_b, "m2", stop="end_turn")])
        projects = self.today(t + 30)
        # A subfolder counts as its repository; a folder outside any
        # repository counts as the project the session started in.
        self.assertEqual(sorted(projects), ["lab", "shop"])
        self.assertEqual(projects["shop"]["spans"], [[t, t + 20, "working"]])
        self.assertEqual(projects["lab"]["spans"], [[t + 20, t + 30, "working"]])
        self.assertEqual(projects["shop"]["commands"], 1)
        self.assertEqual(projects["lab"]["state"], "waiting")
        self.assertEqual(projects["shop"]["state"], "idle")

    def test_a_session_started_outside_any_repository(self):
        t = DAY + 3600
        self.write([prompt(t, self.plain), reply(t + 10, self.plain, "m1", stop="end_turn")])
        self.assertEqual(list(self.today(t + 10)), ["notes"])

    # ----- counts

    def test_edits_commands_and_tests(self):
        t = DAY + 3600
        a = os.path.join(self.repo_a, "a.cs")
        self.write([prompt(t, self.repo_a),
                    reply(t + 1, self.repo_a, "m1", tools=[("Edit", {"file_path": a}), ("Write", {"file_path": a}),
                                                           ("Edit", {"file_path": a + "x"})]),
                    reply(t + 2, self.repo_a, "m2", tools=[("Bash", {"command": "cd x && dotnet test --no-build"}),
                                                           ("Bash", {"command": "python3 -I -m unittest discover -s tests"}),
                                                           ("Bash", {"command": "git status"}),
                                                           ("Bash", {"command": "echo latest-test"})])])
        shop = self.today(t + 3)["shop"]
        self.assertEqual((shop["edits"], shop["files"], shop["commands"], shop["tests"]), (3, 2, 4, 2))

    def test_a_reply_written_as_several_records_counts_its_tokens_once(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 1, self.repo_a, "m1", out=5),
                    reply(t + 2, self.repo_a, "m1", out=40), reply(t + 3, self.repo_a, "m1", out=40)])
        # The same reply, carried on in the next read.
        self.today(t + 3)
        self.write([reply(t + 4, self.repo_a, "m1", out=70), reply(t + 5, self.repo_a, "m2", out=9, stop="end_turn")])
        self.assertEqual(self.today(t + 5)["shop"]["outputTokens"], 79)

    # ----- reading

    def test_a_line_still_being_written_is_read_next_time(self):
        t = DAY + 3600
        line = json.dumps(reply(t + 10, self.repo_a, "m1", stop="end_turn")).encode()
        path = self.write([prompt(t, self.repo_a)], raw_tail=line[:25])
        self.assertEqual(self.today(t + 10)["shop"]["state"], "working")
        with open(path, "ab") as f:
            f.write(line[25:] + b"\n")
        self.assertEqual(self.today(t + 11)["shop"]["state"], "waiting")

    def test_a_rewritten_file_is_read_again(self):
        t = DAY + 3600
        path = self.write([prompt(t, self.repo_a), prompt(t + 1, self.repo_a), reply(t + 2, self.repo_a, "m1")])
        self.today(t + 3)
        os.unlink(path)
        self.write([prompt(t, self.repo_b)])
        projects = self.today(t + 3)
        self.assertEqual(list(projects), ["lab"])

    def test_survives_a_round_trip_through_its_file(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a)])
        self.today(t + 1)
        self.index = agents.Index(json.loads(json.dumps(self.index.to_json())))
        self.write([reply(t + 10, self.repo_a, "m1", stop="end_turn")])
        self.assertEqual(self.today(t + 20)["shop"]["spans"], [[t, t + 10, "working"], [t + 10, t + 20, "waiting"]])

    def test_titles_kept_text_never(self):
        t = DAY + 3600
        self.write([{"type": "ai-title", "aiTitle": "Fix the\nlogin page", "sessionId": "s1"},
                    prompt(t, self.repo_a),
                    reply(t + 1, self.repo_a, "m1", tools=[("Bash", {"command": "curl -H 'token: hunter2' x"})])])
        session = self.today(t + 2)["shop"]["sessions"][0]
        self.assertEqual((session["title"], session["branch"], session["model"]), ("Fix the login page", "main", "claude-test"))
        kept = json.dumps(self.index.to_json())
        self.assertNotIn(SECRET, kept)
        self.assertNotIn("hunter2", kept)

    def test_old_files_arent_read(self):
        path = self.write([prompt(DAY - 5 * 86400, self.repo_a)])
        os.utime(path, (DAY - 5 * 86400, DAY - 5 * 86400))
        self.assertEqual(self.index.scan(self.root, DAY + 10), (0, 0))

    def test_garbage_lines_are_skipped(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a)], raw_tail=b"not json\n[1,2]\n{\"type\": \"user\", \"timestamp\": 5}\n")
        self.assertEqual(self.today(t + 1)["shop"]["prompts"], 1)


class Live(Fixture):
    """~/.claude/sessions/<pid>.json, for Claude Code processes running now."""

    def live(self, sid, status, since, pid=None, started=None):
        folder = os.path.join(self.root, "sessions")
        os.makedirs(folder, exist_ok=True)
        pid = os.getpid() if pid is None else pid
        started = agents._proc_start(os.getpid()) if started is None else started
        with open(os.path.join(folder, f"{pid}.json"), "w") as f:
            json.dump({"pid": pid, "sessionId": sid, "procStart": started, "status": status,
                       "statusUpdatedAt": since * 1000}, f)

    def today_live(self, now):
        self.index.scan(self.root, now)
        live = agents.live_sessions(self.root)
        return {p["name"]: p for p in self.index.today(now, DAY, live)}, live

    def test_an_open_session_waits_for_you_past_the_idle_limit(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", stop="end_turn")], "s1")
        self.live("s1", "idle", t + 20)
        shop, _ = self.today_live(t + 3000)
        shop = shop["shop"]
        self.assertEqual((shop["state"], shop["waitingSince"]), ("waiting", t + 20))
        # The bar still turns idle after IDLE_AFTER.
        self.assertEqual(shop["spans"], [[t, t + 20, "working"], [t + 20, t + 20 + agents.IDLE_AFTER, "waiting"]])
        self.assertTrue(shop["sessions"][0]["open"])

    def test_a_busy_session_works_through_a_long_silent_command(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", tools=[("Bash", {"command": "make"})])], "s1")
        self.live("s1", "busy", t + 20)
        shop = self.today_live(t + 2000)[0]["shop"]
        self.assertEqual((shop["state"], shop["spans"]), ("working", [[t, t + 2000, "working"]]))

    def test_a_closed_session_is_idle_at_once(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", stop="end_turn")], "s1")
        self.live("other", "idle", t)          # Claude Code is running, but not this session
        shop = self.today_live(t + 60)[0]["shop"]
        self.assertEqual((shop["state"], shop["spans"]), ("idle", [[t, t + 20, "working"]]))

    def test_a_stale_file_from_a_reused_pid_is_ignored(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", stop="end_turn")], "s1")
        self.live("s1", "busy", t, started="1")      # the pid runs, but started at another time
        shop, live = self.today_live(t + 60)
        self.assertEqual(live, {})
        self.assertEqual(shop["shop"]["state"], "idle")

    def test_an_unknown_status_falls_back_to_the_session_file(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a), reply(t + 20, self.repo_a, "m1", stop="end_turn")], "s1")
        self.live("s1", "something-new", t + 20)
        self.assertEqual(self.today_live(t + 60)[0]["shop"]["state"], "waiting")

    def test_a_project_with_nothing_to_draw_isnt_listed(self):
        t = DAY + 3600
        self.write([prompt(t, self.repo_a)], "s1")         # closed before any reply
        self.write([prompt(t, self.repo_b), reply(t + 5, self.repo_b, "m1", stop="end_turn")], "s2")
        self.live("other", "idle", t)
        self.assertEqual(list(self.today_live(t + 60)[0]), ["lab"])

    def test_garbage_in_the_sessions_folder(self):
        folder = os.path.join(self.root, "sessions")
        os.makedirs(folder)
        for name, body in (("a.json", "not json"), ("b.json", "[1]"), ("c.json", '{"pid": "1"}'), ("d.key", "x")):
            with open(os.path.join(folder, name), "w") as f:
                f.write(body)
        self.assertEqual(agents.live_sessions(self.root), {})

    def test_no_sessions_folder_means_no_telling(self):
        self.assertIsNone(agents.live_sessions(self.root))


class Command(unittest.TestCase):
    def test_agents_command(self):
        with tempfile.TemporaryDirectory() as d:
            root = os.path.join(d, "claude")
            os.makedirs(os.path.join(root, "projects", "p"))
            now = time.time()
            with open(os.path.join(root, "projects", "p", "s.jsonl"), "w") as f:
                f.write(json.dumps(prompt(now - 30, d)) + "\n")
                f.write(json.dumps(reply(now - 20, d, "m1", stop="end_turn")) + "\n")
            env = dict(os.environ, CLAUDE_CONFIG_DIR=root, XDG_STATE_HOME=os.path.join(d, "state"))
            out = subprocess.run([os.path.join(REPO, "pulse", "bin", "fathom-pulse"), "agents"],
                                 capture_output=True, text=True, env=env, timeout=30)
            self.assertEqual(out.returncode, 0, out.stderr)
            data = json.loads(out.stdout)
            self.assertTrue(data["found"])
            self.assertEqual([(p["prompts"], p["state"]) for p in data["projects"]], [(1, "waiting")])
            index = os.path.join(d, "state", "fathom", "agents.json")
            self.assertEqual(os.stat(index).st_mode & 0o777, 0o600)

    def test_no_claude_code(self):
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, CLAUDE_CONFIG_DIR=os.path.join(d, "none"), XDG_STATE_HOME=d)
            out = subprocess.run([os.path.join(REPO, "pulse", "bin", "fathom-pulse"), "agents"],
                                 capture_output=True, text=True, env=env, timeout=30)
            self.assertEqual(out.returncode, 0, out.stderr)
            data = json.loads(out.stdout)
            self.assertEqual((data["found"], data["projects"]), (False, []))


if __name__ == "__main__":
    unittest.main()

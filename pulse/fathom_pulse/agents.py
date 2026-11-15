"""Agents today: when Claude Code worked on each project, when it waited for
you, and what it did, from its own session files.

Claude Code writes one JSON line per step to
~/.claude/projects/<folder>/<session>.jsonl. This reads them incrementally
(only what's new since the last read) and keeps what it needs in a small
index. It reads timestamps, folders, git branch, model, token counts, tool
names, the paths of edited files and Claude Code's title for each session.
Command text is matched for test runners and then dropped: never stored or
shown. The text of Claude's replies isn't read. Of your messages, only the first 40
characters are looked at, to tell your prompts from notes Claude Code adds
itself; none of it is kept.

A session is in one of three states at any moment:
  working   from your prompt (or a tool result, or a background task's
            notice) until Claude's turn ends
  waiting   from the end of Claude's turn until your next prompt
  idle      any silence longer than IDLE_AFTER, whatever the state was

While Claude Code runs, it also writes ~/.claude/sessions/<pid>.json with
the session it's on and a status, "busy" or "idle". When that file belongs
to a process that's still running (same pid, same start time), it decides
the state now: busy is working (the bar runs to now, even through a long
silent command), idle is waiting for you (since the status changed). A
session with no running process is closed: idle, nothing added after its
last step. Without these files, the session files alone decide.
"""

import datetime
import json
import os
import re
import time

from . import store

IDLE_AFTER = 600            # seconds; measured: 99% of steps are < ~6 min apart
KEEP = 2 * 86400            # seconds of history kept in the index
READ_LIMIT = 64 * 1024 * 1024   # bytes read from one file per call; the rest next time
VERSION = 1

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
TEST_RUNNER = re.compile(
    r"(?<![\w-])(dotnet test|pytest|python3? -m (unittest|pytest)|unittest discover|node --test|"
    r"(npm|pnpm|yarn|bun) (run )?test|go test|cargo test|vitest|jest|phpunit|rspec|mvn test|gradle test)\b")
# User records that Claude Code adds itself, or that run nothing (a slash
# command, a ! shell command): not prompts, and they change no state.
LOCAL_MARKERS = ("<command-name>", "<command-message>", "<local-command", "<bash-", "Caveat:")
INTERRUPTED = "[Request interrupted"
TASK_NOTICE = "<task-notification"
TURN_ENDS = {"end_turn", "stop_sequence", "refusal"}


def _repo_of(folder, cache):
    """The git repository a folder is in, or None."""
    if folder in cache:
        return cache[folder]
    path, found = folder, None
    while path and path != os.path.dirname(path):
        if os.path.exists(os.path.join(path, ".git")):
            found = path
            break
        path = os.path.dirname(path)
    cache[folder] = found
    return found


def _when(stamp):
    """Seconds since the epoch from "2026-11-15T10:26:16.123Z", or None."""
    if not isinstance(stamp, str):
        return None
    try:
        when = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    return when.timestamp() if when.tzinfo else None


def _text_of(content):
    """Only to see which marker a user record starts with."""
    if isinstance(content, str):
        return content.lstrip()[:40]
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                return str(part.get("text", "")).lstrip()[:40]
    return ""


def _is_tool_result(content):
    return isinstance(content, list) and any(
        isinstance(p, dict) and p.get("type") == "tool_result" for p in content)


LIVE_STATES = {"busy": "working", "idle": "waiting"}


def _proc_start(pid):
    """The kernel's start time for a process (field 22 of /proc/<pid>/stat),
    or None if it isn't running."""
    try:
        with open(f"/proc/{int(pid)}/stat", encoding="ascii", errors="replace") as f:
            stat = f.read()
        return stat[stat.rindex(")") + 2:].split()[19]
    except (OSError, ValueError, IndexError):
        return None


def live_sessions(root, proc_start=_proc_start):
    """{session id: {"state", "since"}} for Claude Code processes running
    now, or None when Claude Code keeps no such files here."""
    folder = os.path.join(root, "sessions")
    try:
        names = [n for n in os.listdir(folder) if n.endswith(".json")][:200]
    except OSError:
        return None
    live = {}
    for name in names:
        try:
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                info = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(info, dict):
            continue
        pid, sid, started = info.get("pid"), info.get("sessionId"), info.get("procStart")
        if not isinstance(pid, int) or not isinstance(sid, str) or not isinstance(started, str):
            continue
        if proc_start(pid) != started:
            continue            # gone, or the pid now belongs to something else
        state = LIVE_STATES.get(info.get("status"))
        since = info.get("statusUpdatedAt")
        live[sid] = {"state": state, "since": since / 1000 if isinstance(since, (int, float)) else None}
    return live


def _local_day(t):
    return time.strftime("%Y-%m-%d", time.localtime(t))


class Index:
    """What has been read so far, kept between calls in a JSON file."""

    def __init__(self, data=None):
        data = data if isinstance(data, dict) and data.get("v") == VERSION else {}
        self.files = data.get("files") if isinstance(data.get("files"), dict) else {}
        self.sessions = data.get("sessions") if isinstance(data.get("sessions"), dict) else {}
        self.repos = {}

    def to_json(self):
        return {"v": VERSION, "files": self.files, "sessions": self.sessions}

    # ----- reading

    def scan(self, root, now):
        """Read what's new in every session file touched in the last KEEP
        seconds. Returns (files read, bytes read)."""
        read_files = read_bytes = 0
        projects = os.path.join(root, "projects")
        try:
            folders = os.listdir(projects)
        except OSError:
            folders = []
        seen = set()
        for folder in folders:
            base = os.path.join(projects, folder)
            try:
                names = os.listdir(base)
            except OSError:
                continue
            for name in names:
                if not name.endswith(".jsonl"):
                    continue
                path = os.path.join(base, name)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                known = self.files.get(path)
                if st.st_mtime < now - KEEP and not known:
                    continue
                seen.add(path)
                if known and known.get("inode") == st.st_ino and known.get("offset", 0) == st.st_size:
                    continue
                n = self._read(path, st, now)
                if n:
                    read_files += 1
                    read_bytes += n
        for path in list(self.files):
            if path not in seen:
                self._forget(path)
        self._prune(now)
        return read_files, read_bytes

    def _forget(self, path):
        info = self.files.pop(path, None)
        if info:
            self.sessions.pop(info.get("session"), None)

    def _read(self, path, st, now):
        info = self.files.get(path)
        if not info or info.get("inode") != st.st_ino or info.get("offset", 0) > st.st_size:
            self._forget(path)
            info = {"inode": st.st_ino, "offset": 0, "session": path}
            self.files[path] = info
        try:
            with open(path, "rb") as f:
                f.seek(info["offset"])
                chunk = f.read(READ_LIMIT)
        except OSError:
            return 0
        # Only whole lines: the last one may still be being written.
        end = chunk.rfind(b"\n") + 1
        if end == 0:
            return 0
        session = self.sessions.setdefault(info["session"], _new_session())
        for line in chunk[:end].split(b"\n"):
            if line:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if isinstance(record, dict):
                    self._step(session, record, now)
        info["offset"] += end
        return end

    # ----- one record

    def _project(self, session, cwd):
        """The git repository the step ran in; outside any repository, the
        project the session started in."""
        if isinstance(cwd, str) and cwd.startswith("/"):
            repo = _repo_of(cwd, self.repos)
            if not session["launch"]:
                session["launch"] = repo or cwd
            return repo or session["launch"]
        if session["last"]:
            return session["last"][2]
        return session["launch"] or "?"

    def _step(self, s, r, now):
        kind = r.get("type")
        if kind == "ai-title":
            if isinstance(r.get("aiTitle"), str):
                s["title"] = store.clean(r["aiTitle"], 80)
            return
        if kind not in ("user", "assistant") or r.get("isSidechain"):
            return
        t = _when(r.get("timestamp"))
        if t is None or t < now - KEEP:
            return
        if isinstance(r.get("gitBranch"), str) and r["gitBranch"]:
            s["branch"] = store.clean(r["gitBranch"], 60)
        message = r.get("message") if isinstance(r.get("message"), dict) else {}
        content = message.get("content")
        project = self._project(s, r.get("cwd"))
        count = None

        if kind == "user":
            if r.get("isMeta") or r.get("isCompactSummary"):
                return
            if _is_tool_result(content):
                state = "working"
            else:
                text = _text_of(content)
                if text.startswith(INTERRUPTED):
                    state = "waiting"
                elif text.startswith(TASK_NOTICE):
                    state = "working"
                elif text.startswith(LOCAL_MARKERS):
                    return
                else:
                    state, count = "working", "prompts"
        else:
            state = "waiting" if (r.get("isApiErrorMessage") or message.get("stop_reason") in TURN_ENDS) else "working"
            if isinstance(message.get("model"), str) and not message["model"].startswith("<"):
                s["model"] = store.clean(message["model"], 40)

        day = self._counts(s, t, project)
        if count:
            day[count] += 1
        if kind == "assistant":
            self._tally(s, message, day)

        self._move(s, t, state, project)

    def _tally(self, s, message, day):
        # One reply is written as several records, each carrying the reply's
        # usage so far: count each reply's tokens once.
        mid = message.get("id")
        usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
        out = usage.get("output_tokens") if isinstance(usage.get("output_tokens"), int) else 0
        last_id, last_out = s["reply"]
        if mid and mid == last_id:
            if out > last_out:
                day["tokens"] += out - last_out
                s["reply"] = [mid, out]
        else:
            day["tokens"] += out
            s["reply"] = [mid, out]
        content = message.get("content")
        for part in content if isinstance(content, list) else []:
            if not isinstance(part, dict) or part.get("type") != "tool_use":
                continue
            name = part.get("name")
            args = part.get("input") if isinstance(part.get("input"), dict) else {}
            if name in EDIT_TOOLS:
                day["edits"] += 1
                path = args.get("file_path") or args.get("notebook_path")
                if isinstance(path, str) and path not in day["files"] and len(day["files"]) < 500:
                    day["files"].append(path)
            elif name == "Bash":
                day["commands"] += 1
                command = args.get("command")
                if isinstance(command, str) and TEST_RUNNER.search(command):
                    day["tests"] += 1

    def _counts(self, s, t, project):
        days = s["days"].setdefault(_local_day(t), {})
        return days.setdefault(project, {"prompts": 0, "edits": 0, "files": [], "commands": 0,
                                                "tests": 0, "tokens": 0})

    def _move(self, s, t, state, project):
        """Close the stretch since the last step, then start a new one."""
        last = s["last"]
        if last:
            t0, state0, project0 = last
            if t < t0:          # out of order: keep the stretch, move on
                t = t0
            end = t0 + min(t - t0, IDLE_AFTER)
            _add(s["spans"], t0, end, state0, project0)
        else:
            s["start"] = t
        s["last"] = [t, state, project]
        s["end"] = t

    def _prune(self, now):
        cut = now - KEEP
        keep_days = {_local_day(now), _local_day(now - 86400)}
        for key, s in list(self.sessions.items()):
            s["spans"] = [sp for sp in s["spans"] if sp[1] >= cut]
            s["days"] = {d: v for d, v in s["days"].items() if d in keep_days}

    # ----- today

    def today(self, now, day_start, live=None):
        """The day so far, by project. `live` is live_sessions(), or None
        when there's no telling which sessions are open."""
        by_project = {}
        for key, s in self.sessions.items():
            spans = list(s["spans"])
            sid = os.path.splitext(os.path.basename(key))[0]
            open_now = (live or {}).get(sid)
            if s["last"]:
                t0, state0, project0 = s["last"]
                if open_now and open_now["state"] == "working":
                    spans.append([t0, now, "working", project0])
                elif live is None or open_now:
                    spans.append([t0, min(now, t0 + IDLE_AFTER), state0, project0])
            state_now = _state_now(s, now, live, open_now)
            mine = {}
            for start, end, state, project in spans:
                start, end = max(start, day_start), min(end, now)
                if end > start:
                    mine.setdefault(project, []).append((start, end, state))
            counts = s["days"].get(_local_day(day_start), {})
            for project in set(mine) | set(counts):
                p = by_project.setdefault(project, {"spans": [], "sessions": [], "prompts": 0, "edits": 0,
                                                    "files": set(), "commands": 0, "tests": 0, "tokens": 0})
                p["spans"].extend(mine.get(project, []))
                c = counts.get(project)
                if c:
                    for k in ("prompts", "edits", "commands", "tests", "tokens"):
                        p[k] += c[k]
                    p["files"].update(c["files"])
                own = mine.get(project, [])
                if own or (c and c["prompts"]):
                    p["sessions"].append({
                        "title": s.get("title") or "", "branch": s.get("branch") or "", "model": s.get("model") or "",
                        "start": round(min((a for a, _, _ in own), default=s["start"] or day_start)),
                        "end": round(max((b for _, b, _ in own), default=s["end"] or day_start)),
                        "working": round(_total(_merge(own), "working")),
                        "waiting": round(_total(_merge(own), "waiting")),
                        "prompts": c["prompts"] if c else 0,
                        # Now: only where the session's latest step was.
                        "state": state_now if s["last"] and s["last"][2] == project else "idle",
                        "open": bool(open_now),
                        "since": round(open_now["since"]) if open_now and open_now.get("since") and s["last"]
                                 and s["last"][2] == project else None,
                    })
        out = []
        home = os.path.expanduser("~")
        for project, p in by_project.items():
            merged = _merge(p["spans"])
            if not merged:
                continue        # nothing to draw: a prompt in a session closed before any reply
            name = os.path.basename(project.rstrip("/")) if project and project != home else "~"
            if project == home:
                shown = "~"
            elif project and project.startswith(home + "/"):
                shown = "~" + project[len(home):]
            else:
                shown = project or ""
            out.append({
                "id": project or "?", "name": store.clean(name, 60), "path": store.clean(shown, 120),
                "working": round(_total(merged, "working")), "waiting": round(_total(merged, "waiting")),
                "first": round(merged[0][0]) if merged else None, "last": round(merged[-1][1]) if merged else None,
                "spans": [[round(a), round(b), st] for a, b, st in merged][-300:],
                "prompts": p["prompts"], "edits": p["edits"], "files": len(p["files"]),
                "commands": p["commands"], "tests": p["tests"], "outputTokens": p["tokens"],
                "sessions": sorted(p["sessions"], key=lambda x: -x["end"])[:10],
                "state": max((x["state"] for x in p["sessions"]), key=_STATE_ORDER.index, default="idle"),
                "waitingSince": min((x["since"] for x in p["sessions"] if x["state"] == "waiting" and x["since"]),
                                    default=None),
            })
        out.sort(key=lambda x: -(x["last"] or 0))
        return out


_STATE_ORDER = ["idle", "waiting", "working"]


def _state_now(s, now, live=None, open_now=None):
    if not s["last"]:
        return "idle"
    if open_now and open_now.get("state"):
        return open_now["state"]
    if live is not None and not open_now:
        return "idle"           # closed
    t0, state0, _ = s["last"]
    return state0 if now - t0 < IDLE_AFTER else "idle"


def _new_session():
    return {"start": None, "end": None, "last": None, "launch": None, "title": "", "branch": "", "model": "",
            "spans": [], "days": {}, "reply": [None, 0]}


def _add(spans, start, end, state, project):
    if end <= start:
        return
    if spans:
        a, b, st, pr = spans[-1]
        if st == state and pr == project and abs(start - b) < 1e-6:
            spans[-1][1] = end
            return
    spans.append([start, end, state, project])


def _merge(spans):
    """Overlapping stretches (two sessions at once) as one line: working
    wins over waiting. Sorted, non-overlapping [start, end, state]."""
    if not spans:
        return []
    points = sorted({x for a, b, _ in spans for x in (a, b)})
    out = []
    for a, b in zip(points, points[1:]):
        states = [st for s0, s1, st in spans if s0 <= a and s1 >= b]
        if not states:
            continue
        state = "working" if "working" in states else "waiting"
        if out and out[-1][2] == state and abs(out[-1][1] - a) < 1e-6:
            out[-1][1] = b
        else:
            out.append([a, b, state])
    return out


def _total(merged, state):
    return sum(b - a for a, b, st in merged if st == state)


# ---------------------------------------------------------------- the command

def claude_root():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def local_midnight(now):
    t = time.localtime(now)
    return time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 0, 0, 0, 0, 0, -1))


def report(index_path, root=None, now=None):
    """Read what's new, save the index, and return today as a dict."""
    now = time.time() if now is None else now
    started = time.monotonic()
    try:
        with open(index_path, encoding="utf-8") as f:
            index = Index(json.load(f))
    except (OSError, ValueError):
        index = Index()
    root = root or claude_root()
    files, nbytes = index.scan(root, now)
    live = live_sessions(root)
    projects = index.today(now, local_midnight(now), live)
    return index, {
        "agent": "Claude Code",
        "found": os.path.isdir(os.path.join(root, "projects")),
        "day": _local_day(now), "start": round(local_midnight(now)), "time": round(now),
        "idleAfter": IDLE_AFTER,
        "open": len(live) if live is not None else None,
        "projects": projects[:20],
        "read": {"files": files, "bytes": nbytes, "ms": round((time.monotonic() - started) * 1000)},
    }

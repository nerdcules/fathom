"""Shared parts of Fathom Mail: where things live, the keyring, HTTP and
desktop notifications. Providers (outlook.py, and later others) build on
these; nothing here knows about any one mail service."""

import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "fathom")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "fathom")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mail.json")
STATE_FILE = os.path.join(STATE_DIR, "mail.json")

MAX_RESPONSE = 4 * 1024 * 1024
TIMEOUT = 20


class MailError(Exception):
    """Something the user should hear about, in words they can act on."""


class SignedOut(MailError):
    """The account needs signing in again."""


# ---------------------------------------------------------------- files

def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, value):
    """Write atomically, readable only by you."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".mail-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_config():
    config = read_json(CONFIG_FILE, {})
    if not isinstance(config, dict):
        config = {}
    accounts = config.get("accounts")
    config["accounts"] = [a for a in accounts if isinstance(a, dict) and a.get("id")] if isinstance(accounts, list) else []
    return config


def save_config(config):
    write_json(CONFIG_FILE, config)


# ---------------------------------------------------------------- keyring

def _secret_attrs(account_id):
    return ["application", "fathom-mail", "account", account_id]


def secret_get(account_id):
    try:
        out = subprocess.run(["secret-tool", "lookup", *_secret_attrs(account_id)],
                             capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MailError(f"Couldn't read the keyring: {e}") from e
    return out.stdout if out.returncode == 0 and out.stdout else None


def secret_set(account_id, label, value):
    try:
        out = subprocess.run(["secret-tool", "store", f"--label={label}", *_secret_attrs(account_id)],
                             input=value, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MailError(f"Couldn't write to the keyring: {e}") from e
    if out.returncode != 0:
        raise MailError(f"Couldn't write to the keyring: {out.stderr.strip()[:200]}")


def secret_clear(account_id):
    subprocess.run(["secret-tool", "clear", *_secret_attrs(account_id)], capture_output=True, timeout=15)


# ---------------------------------------------------------------- HTTP

class HttpError(MailError):
    def __init__(self, status, body):
        self.status = status
        self.body = body
        super().__init__(f"HTTP {status}")

    def json(self):
        try:
            return json.loads(self.body)
        except ValueError:
            return {}


def request(method, url, *, form=None, headers=None):
    """HTTPS only, with a timeout and a cap on how much is read."""
    if not url.startswith("https://"):
        raise MailError("Refusing a non-HTTPS address")
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "User-Agent": "fathom-mail",
        "Accept": "application/json",
        **(headers or {}),
    })
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            body = resp.read(MAX_RESPONSE + 1)
    except urllib.error.HTTPError as e:
        raise HttpError(e.code, e.read(MAX_RESPONSE).decode("utf-8", "replace")) from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise MailError(f"Couldn't reach the mail service ({getattr(e, 'reason', e)})") from None
    if len(body) > MAX_RESPONSE:
        raise MailError("The mail service sent more than expected")
    try:
        return json.loads(body.decode("utf-8")) if body else {}
    except ValueError:
        raise MailError("The mail service sent something unreadable") from None


# ---------------------------------------------------------------- text

_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")
_SPACE = re.compile(r"[ \t\r\n]+")


def plain(value, limit=200):
    """One line of text, without control characters, at most `limit` long."""
    text = _CONTROL.sub(" ", str(value or ""))
    text = _SPACE.sub(" ", text).strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def escape_markup(text):
    """Notification bodies may be read as markup; make every character literal."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------- notifications

ENVELOPE = "\U000f01ee"   # nf-md-email
MAX_SINGLE = 3            # more new mail than this at once becomes one summary


def notify(headline, body="", *, open_argv=None, urgency=1, replaces=0):
    """Send a notification the way omarchy-notification-send does: straight
    to the notification service over D-Bus, never through notify-send's
    option parsing, so a subject like "--hint=..." stays text. Clicking it
    runs open_argv."""
    hints = ["urgency", "y", str(urgency), "omarchy-glyph", "s", ENVELOPE]
    if open_argv:
        hints += ["omarchy-exec-argv", "s", json.dumps(open_argv)]
    argv = ["busctl", "--user", "--", "call",
            "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
            "Mail", str(replaces), "", headline, body, "0",
            str(len(hints) // 3), *hints, "-1"]
    try:
        subprocess.run(argv, capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass


def safe_link(url, allowed):
    """A link to open on click, only if it points where the provider says
    its mail lives."""
    url = str(url or "")
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError:
        return None
    if parts.scheme != "https" or parts.hostname not in allowed or len(url) > 2048:
        return None
    return url


def announce(account_label, messages, inbox_link):
    """Notifications for new mail: one each for a few, one summary for more."""
    if not messages:
        return
    if len(messages) > MAX_SINGLE:
        senders = []
        for m in messages:
            if m["sender"] not in senders:
                senders.append(m["sender"])
        shown = ", ".join(senders[:4]) + (f" and {len(senders) - 4} more" if len(senders) > 4 else "")
        notify(f"{len(messages)} new emails", escape_markup(plain(f"From {shown}", 300)),
               open_argv=["xdg-open", inbox_link] if inbox_link else None)
        return
    for m in messages:
        body = plain(m["subject"] or "(no subject)", 160)
        if m.get("preview"):
            body += "\n" + plain(m["preview"], 160)
        link = m.get("link") or inbox_link
        notify(plain(m["sender"], 80) or account_label, escape_markup(body),
               open_argv=["xdg-open", link] if link else None)


def now():
    return int(time.time())

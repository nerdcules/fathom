"""What Sentinel notices, as pure functions and small stateful detectors:
journal lines in, events out. No I/O here, so it can all be tested."""

import ipaddress
import re
import time

MAX_TEXT = 200

_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")


def plain(value, limit=MAX_TEXT):
    text = _CONTROL.sub(" ", str(value or ""))
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def event(kind, level, title, detail="", when=None, **data):
    """One thing Sentinel saw. level is info, warn or bad."""
    when = int(when or time.time())
    return {"id": f"{kind}-{when}-{abs(hash((title, detail))) % 100000}", "time": when, "kind": kind,
            "level": level, "title": plain(title, 120), "detail": plain(detail), "data": data}


# ---------------------------------------------------------------- firewall

_KV = re.compile(r"\b(IN|OUT|SRC|DST|PROTO|SPT|DPT)=(\S*)")


def parse_ufw(message):
    """A '[UFW BLOCK]' kernel line as {src, dst, proto, dport, iface}, or None."""
    text = str(message or "")
    if "[UFW BLOCK]" not in text:
        return None
    fields = dict(_KV.findall(text))
    src = fields.get("SRC", "")
    try:
        ipaddress.ip_address(src)
    except ValueError:
        return None
    return {"src": src, "dst": fields.get("DST", ""), "proto": fields.get("PROTO", ""),
            "dport": fields.get("DPT", ""), "iface": fields.get("IN", ""), "inbound": bool(fields.get("IN"))}


def is_public(ip):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return addr.is_global


class ScanDetector:
    """Many different ports blocked from one address in a short time is a port
    scan; ordinary blocked chatter (a printer, a TV) hits the same few ports."""

    def __init__(self, ports=12, window=300, quiet=3600):
        self.ports, self.window, self.quiet = ports, window, quiet
        self.seen = {}      # src -> [(time, port)]
        self.alerted = {}   # src -> time

    def feed(self, block, when):
        if not block or not block.get("dport"):
            return None
        src = block["src"]
        hits = [h for h in self.seen.get(src, []) if when - h[0] <= self.window]
        hits.append((when, block["dport"]))
        self.seen[src] = hits[-200:]
        ports = {p for _, p in hits}
        last = self.alerted.get(src)
        if len(ports) >= self.ports and (last is None or when - last > self.quiet):
            self.alerted[src] = when
            where = "the internet" if is_public(src) else "your network"
            return event("scan", "bad", f"Port scan from {src} blocked",
                         f"{len(ports)} ports probed in {self.window // 60} minutes, from {where}. The firewall stopped all of it.",
                         when, src=src)
        return None


def top_sources(sources, n=4):
    """The addresses blocked most today, as status shows them: ones from the
    internet first, then the rest, each by count. Local chatter (a TV, the
    router) easily outnumbers a probe from outside."""
    ranked = sorted(sources.items(), key=lambda kv: (not is_public(kv[0]), -kv[1], kv[0]))
    return [{"src": short_ip(src), "count": count, "public": is_public(src)} for src, count in ranked[:n]]


def short_ip(ip):
    """ufw logs IPv6 in full (2a06:98c1:0000:...); show the usual short form."""
    try:
        return str(ipaddress.ip_address(ip))
    except ValueError:
        return ip

# ---------------------------------------------------------------- sign-ins

_SUDO_CMD = re.compile(r"^\s*(\S+) : .*COMMAND=(.*)$")
_SUDO_BAD = re.compile(r"^\s*(\S+) : (\d+) incorrect password attempts?")
_PAM_FAIL = re.compile(r"pam_unix\(([\w-]+):auth\): authentication failure.*?(?:user=(\S+))?$")
_SSH_FAIL = re.compile(r"(?:Failed password|Invalid user|Failed publickey) (?:for (?:invalid user )?)?(\S+)? ?from (\S+)")


def parse_auth(identifier, message):
    """A journal line about signing in or sudo, as a small dict, or None."""
    text = str(message or "")
    ident = str(identifier or "")
    if ident == "sudo":
        # sudo's "N incorrect password attempts" sums up failures PAM has
        # already reported one by one, so it isn't counted again.
        if _SUDO_BAD.match(text):
            return None
        m = _SUDO_CMD.match(text)
        if m:
            return {"type": "sudo", "user": m.group(1), "command": m.group(2)}
    if ident == "sshd":
        m = _SSH_FAIL.search(text)
        if m:
            return {"type": "fail", "service": "ssh", "user": m.group(1) or "", "from": m.group(2), "count": 1}
        if "Accepted " in text:
            m = re.search(r"Accepted \S+ for (\S+) from (\S+)", text)
            if m:
                return {"type": "login", "service": "ssh", "user": m.group(1), "from": m.group(2)}
    m = _PAM_FAIL.search(text)
    if m:
        return {"type": "fail", "service": m.group(1), "user": m.group(2) or "", "count": 1}
    return None


class FailureDetector:
    """A wrong password now and then is you; several in a few minutes, or any
    from another machine, is worth a look."""

    def __init__(self, limit=3, window=600, quiet=1800):
        self.limit, self.window, self.quiet = limit, window, quiet
        self.times = []
        self.alerted = None

    def feed(self, auth, when):
        if not auth or auth.get("type") != "fail":
            return None
        if auth.get("from"):
            return event("auth", "bad", f"Failed {auth['service']} sign-in from {auth['from']}",
                         f"Someone tried to sign in as {auth.get('user') or 'an unknown user'} from another machine.",
                         when, src=auth["from"], service=auth["service"])
        self.times = [t for t in self.times if when - t <= self.window] + [when] * max(1, auth.get("count", 1))
        if len(self.times) >= self.limit and (self.alerted is None or when - self.alerted > self.quiet):
            self.alerted = when
            return event("auth", "warn", f"{len(self.times)} wrong passwords in {self.window // 60} minutes",
                         f"Most recently for {auth['service']}. If that wasn't you, lock the screen.",
                         when, service=auth["service"])
        return event("auth", "info", f"Wrong password for {auth['service']}", "", when, service=auth["service"])


# ---------------------------------------------------------------- devices

def is_private_mac(mac):
    """Phones and laptops often use a random address per network."""
    try:
        return bool(int(str(mac).split(":")[0], 16) & 0x02)
    except (ValueError, IndexError):
        return False


def oui_index(lines):
    """hwdata's oui.txt as {"001A2B": "Vendor"}."""
    index = {}
    for line in lines:
        m = re.match(r"^\s*([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})\s+\(hex\)\s+(.+?)\s*$", line)
        if m:
            index[(m.group(1) + m.group(2) + m.group(3)).upper()] = plain(m.group(4), 60)
    return index


def vendor(mac, index):
    if is_private_mac(mac):
        return "Private address"
    key = str(mac).replace(":", "").upper()[:6]
    return index.get(key, "")


def neighbours(entries, iface):
    """`ip -j neigh` entries on one interface that have a hardware address."""
    out = {}
    for e in entries if isinstance(entries, list) else []:
        if not isinstance(e, dict) or e.get("dev") != iface:
            continue
        mac = str(e.get("lladdr", "")).lower()
        if not re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", mac):
            continue
        states = e.get("state") or []
        if "FAILED" in states or "INCOMPLETE" in states:
            continue
        ip = str(e.get("dst", ""))
        # One device can answer on IPv4 and IPv6; show its IPv4 address.
        if mac in out and ":" in ip and ":" not in out[mac]:
            continue
        out[mac] = ip
    return out


class DeviceWatch:
    """New devices on the network you're on. On a network seen for the first
    time it learns quietly for a while, so joining a café's Wi-Fi isn't a
    flood of alerts."""

    LEARN = 600

    def __init__(self, known=None):
        # network id -> {"since": t, "devices": {mac: {ip, first, last, vendor, trusted}}}
        self.networks = known if isinstance(known, dict) else {}

    def feed(self, network, found, index, when):
        if not network:
            return []
        net = self.networks.setdefault(network, {"since": when, "devices": {}})
        learning = when - net["since"] < self.LEARN
        events = []
        for mac, ip in found.items():
            dev = net["devices"].get(mac)
            if dev:
                dev.update(ip=ip, last=when)
                continue
            dev = {"ip": ip, "first": when, "last": when, "vendor": vendor(mac, index), "trusted": learning}
            net["devices"][mac] = dev
            if not learning:
                label = dev["vendor"] or "Unknown maker"
                events.append(event("device", "warn", f"New device on your network: {ip}",
                                    f"{label} · {mac}", when, mac=mac, ip=ip, network=network))
        # Keep the list from growing forever: drop devices unseen for 60 days.
        for mac in [m for m, d in net["devices"].items() if when - d.get("last", 0) > 60 * 86400]:
            del net["devices"][mac]
        return events


# ---------------------------------------------------------------- USB

def usb_event(name, info, when):
    label = " ".join(x for x in (info.get("vendor", ""), info.get("model", "")) if x) or name
    size = info.get("size", 0)
    detail = f"{label} · {size / 1e9:.1f} GB" if size else label
    return event("usb", "info", "USB storage plugged in", detail, when, device=name)


# ---------------------------------------------------------------- integrity

def integrity_changes(previous, current):
    """Files that differ from their package now but didn't last time."""
    before = {(f.get("pkg"), f.get("path")) for f in (previous or [])}
    return [f for f in (current or []) if (f.get("pkg"), f.get("path")) not in before]


def integrity_event(seen, checked, when=None):
    """The event for a finished file check. seen is what the last check
    found (None before the first one); checked is integrity.json."""
    altered = checked.get("altered") or []
    total = checked.get("alteredCount", len(altered))
    files, packages = checked.get("files", 0), checked.get("packages", 0)
    if seen is None:
        if total:
            return event("files", "info", "System files: first check done",
                         f"{total} of {files} files differ from their packages. "
                         "From now on, only new differences are flagged.", when)
        return event("files", "info", "System files match their packages",
                     f"{files} files in {packages} packages checked", when)
    changed = integrity_changes(seen.get("altered"), altered)
    if changed:
        shown = ", ".join(f["path"] for f in changed[:3]) + (f" and {len(changed) - 3} more" if len(changed) > 3 else "")
        return event("files", "warn", f"{len(changed)} system file{'s' if len(changed) != 1 else ''} changed",
                     f"{shown} no longer match{'es' if len(changed) == 1 else ''} their package.", when)
    return event("files", "info", "No new changes to system files",
                 f"{files} files in {packages} packages checked", when)

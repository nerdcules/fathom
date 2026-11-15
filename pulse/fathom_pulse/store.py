"""Pulse's memory: the spans of the last hour, and per-minute summaries for a
day, turned into a map of what calls what.

Plain Python: spans arrive here already decoded (see otlp.py), so everything
in this file can be tested without protobuf.

The map:
  - a service is a node; its requests are its server and consumer spans (or,
    for a service that only runs jobs, its root spans)
  - a span whose parent is in another service is an edge, caller -> callee
  - a client or producer span with no child in another service calls
    something that sends no telemetry of its own (a database, a cache, a
    model, an HTTP API): that becomes an inferred node, named from the span's
    attributes
"""

import bisect
import math
import threading
import time
from collections import deque

KINDS = {0: "unspecified", 1: "internal", 2: "server", 3: "client", 4: "producer", 5: "consumer"}
INBOUND = {"server", "consumer"}
OUTBOUND = {"client", "producer"}

# Attributes kept from each span: the ones that name what it called, plus
# a few for the inspector. Everything else is dropped on arrival.
WANTED = (
    "peer.service", "db.system", "db.system.name", "db.name", "db.namespace",
    "messaging.system", "messaging.destination.name",
    "gen_ai.system", "gen_ai.provider.name", "gen_ai.request.model",
    "server.address", "server.port", "net.peer.name", "net.peer.port",
    "url.full", "http.url", "http.route", "http.request.method", "http.method",
    "http.response.status_code", "rpc.system", "rpc.service",
)

# Default ports of things that often run beside an app without telemetry of
# their own. Only a label: "localhost:11434" reads better as "ollama". The
# address is kept as the node's detail.
KNOWN_PORTS = {
    11434: "ollama", 5432: "postgres", 3306: "mysql", 1433: "sql server",
    6379: "redis", 6333: "qdrant", 6334: "qdrant", 27017: "mongodb",
    9200: "elasticsearch", 5672: "rabbitmq", 9092: "kafka", 8000: "chroma",
}

# Latency buckets for the day's summaries: 0.1 ms to 10 minutes, each 25%
# wider than the last. A p95 from them is the upper edge of its bucket, so
# up to 25% high. The hour in memory uses exact span durations instead.
BUCKETS = []
_edge = 0.1
while _edge < 600_000:
    BUCKETS.append(_edge)
    _edge *= 1.25
BUCKETS.append(math.inf)

MAX_TEXT = 200
NO_ATTRS = {}                      # shared by spans without attributes; never changed


def clean(value, limit=MAX_TEXT):
    """Telemetry comes from any app (or container) that can reach the port:
    keep it to one short line of printable text."""
    text = "".join(ch if ch.isprintable() else " " for ch in str(value))
    text = " ".join(text.split())
    return text[:limit - 1] + "…" if len(text) > limit else text


class Span:
    __slots__ = ("trace", "id", "parent", "service", "instance", "name", "kind",
                 "start", "end", "error", "message", "attrs", "rolled")

    def __init__(self, trace, id, parent, service, name, kind, start, end,
                 error=False, message="", attrs=None, instance=""):
        self.trace, self.id, self.parent = trace, id, parent or ""
        self.service, self.instance = service, instance
        self.name, self.kind = name, kind
        self.start, self.end = start, end
        self.error, self.message = error, message
        self.attrs = attrs or NO_ATTRS
        self.rolled = False

    @property
    def ms(self):
        return max(0.0, (self.end - self.start) * 1000.0)


# ---------------------------------------------------------------- targets

def service_id(name):
    return "svc:" + name


def _port(value):
    try:
        port = int(value)
        return port if 0 < port < 65536 else None
    except (TypeError, ValueError):
        return None


def _host_port(attrs):
    host = attrs.get("server.address") or attrs.get("net.peer.name")
    port = _port(attrs.get("server.port") or attrs.get("net.peer.port"))
    if not host:
        url = attrs.get("url.full") or attrs.get("http.url") or ""
        rest = url.split("://", 1)[1] if "://" in url else ""
        hostport = rest.split("/", 1)[0].rsplit("@", 1)[-1]
        if hostport.startswith("["):                      # [::1]:11434
            host, _, tail = hostport[1:].partition("]")
            port = port or _port(tail.lstrip(":"))
        elif hostport.count(":") == 1:
            host, tail = hostport.split(":")
            port = port or _port(tail)
        else:
            host = hostport
        if not port and url.startswith("https://"):
            port = 443
        elif not port and url.startswith("http://"):
            port = 80
    return (clean(host, 100) if host else ""), port


def target(span):
    """What an outbound span called, as (node id, name, kind, detail), or
    None when the span doesn't say."""
    a = span.attrs
    hostport = _host_port(a)
    where = f"{hostport[0]}:{hostport[1]}" if hostport[0] and hostport[1] else hostport[0]
    if a.get("peer.service"):
        name = clean(a["peer.service"], 80)
        return service_id(name), name, "service", where
    db = a.get("db.system.name") or a.get("db.system")
    if db:
        name = clean(db, 40)
        return f"db:{name}@{where}", name, "database", where
    mq = a.get("messaging.system")
    if mq:
        name = clean(mq, 40)
        return f"mq:{name}@{where}", name, "messaging", where
    ai = a.get("gen_ai.provider.name") or a.get("gen_ai.system")
    if ai:
        name = clean(ai, 40)
        return f"ai:{name}@{where}", name, "ai", where
    if where:
        known = KNOWN_PORTS.get(hostport[1])
        return f"net:{where}", known or where, "ai" if known == "ollama" else "external", where
    return None


# ---------------------------------------------------------------- summaries

class Agg:
    """Count, errors and latencies of one node or edge."""
    __slots__ = ("count", "errors", "ms", "hist")

    def __init__(self, exact=True):
        self.count = 0
        self.errors = 0
        self.ms = [] if exact else None
        self.hist = None if exact else [0] * len(BUCKETS)

    def add(self, ms, error):
        self.count += 1
        self.errors += bool(error)
        if self.ms is not None:
            self.ms.append(ms)
        else:
            self.hist[bisect.bisect_left(BUCKETS, ms)] += 1

    def merge(self, other):
        """Add a day summary (histogram) into this one."""
        self.count += other["count"]
        self.errors += other["errors"]
        for i, n in enumerate(other["hist"]):
            self.hist[i] += n

    def p95(self):
        if not self.count:
            return None
        if self.ms is not None:
            ordered = sorted(self.ms)
            return ordered[min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1)]
        rank = math.ceil(0.95 * self.count)
        seen = 0
        for i, n in enumerate(self.hist):
            seen += n
            if seen >= rank:
                return BUCKETS[i] if BUCKETS[i] != math.inf else BUCKETS[-2]
        return None

    def to_json(self):
        return {"count": self.count, "errors": self.errors, "hist": self.hist}


# ---------------------------------------------------------------- the store

class Store:
    def __init__(self, keep=3600, day=86400, max_spans=100_000, grace=120, clock=time.time):
        self.keep, self.day, self.max_spans, self.grace = keep, day, max_spans, grace
        self.clock = clock
        self.lock = threading.Lock()
        self.spans = deque()          # arrival order
        self.pending = []             # not yet folded into a minute summary
        self.cache = {}               # window -> (computed at, snapshot)
        self.cache_for = 5            # seconds
        self.by_id = {}               # (trace, id) -> Span
        self.child_services = {}      # (trace, parent id) -> the service its children are in
                                      # (a set only when there are several: saves memory)
        self.services = {}            # name -> {"lastSeen", "sdk", "version", "instances": set}
        self.minutes = {}             # minute (epoch s) -> {"nodes": {id: agg}, "edges": {"a\0b": agg}, "names": {id: [name, kind, detail]}}
        self.errors = deque(maxlen=30)
        self.received = 0
        self.dropped = 0
        self.started = clock()

    # ----- arrival

    def add(self, spans, resource=None):
        """Spans from one export, all from the same resource."""
        now = self.clock()
        resource = resource or {}
        with self.lock:
            for s in spans:
                key = (s.trace, s.id)
                if key in self.by_id:
                    continue
                self.received += 1
                self.spans.append(s)
                self.pending.append(s)
                self.by_id[key] = s
                if s.parent:
                    # Parents usually arrive after their children (they end
                    # last), so record the child's service and compare when
                    # the map is drawn.
                    k = (s.trace, s.parent)
                    seen = self.child_services.get(k)
                    if seen is None:
                        self.child_services[k] = s.service
                    elif isinstance(seen, set):
                        seen.add(s.service)
                    elif seen != s.service:
                        self.child_services[k] = {seen, s.service}
                if s.error:
                    self.errors.append({"time": int(s.end), "service": s.service, "name": s.name,
                                        "message": s.message, "trace": s.trace})
            if spans:
                svc = spans[0].service
                info = self.services.setdefault(svc, {"lastSeen": 0, "sdk": "", "version": "", "instances": set()})
                info["lastSeen"] = int(now)
                info["sdk"] = clean(resource.get("telemetry.sdk.language", info["sdk"]), 40)
                info["version"] = clean(resource.get("service.version", info["version"]), 60)
                if resource.get("service.instance.id") and len(info["instances"]) < 100:
                    info["instances"].add(clean(resource["service.instance.id"], 80))
            self._evict(now)

    def _evict(self, now):
        while self.spans and (len(self.spans) > self.max_spans or self.spans[0].end < now - self.keep):
            s = self.spans.popleft()
            if len(self.spans) >= self.max_spans:
                self.dropped += 1
            if not s.rolled:
                self._roll_one(s)
            self.by_id.pop((s.trace, s.id), None)
            self.child_services.pop((s.trace, s.id), None)

    # ----- what a span adds to the map

    def _contributions(self, s):
        """[(node or edge key, (name, kind, detail) or None)] this span counts
        toward. Node keys are ids; edge keys are "from\\0to"."""
        out = []
        parent = self.by_id.get((s.trace, s.parent)) if s.parent else None
        me = service_id(s.service)
        if s.kind in INBOUND or (not s.parent and s.kind not in OUTBOUND):
            out.append((me, None))
        if parent is not None and parent.service != s.service:
            out.append((service_id(parent.service) + "\0" + me, None))
        children = self.child_services.get((s.trace, s.id), ())
        if isinstance(children, str):
            children = (children,)
        if s.kind in OUTBOUND and not any(c != s.service for c in children):
            t = target(s)
            if t:
                tid, name, kind, detail = t
                out.append((tid, (name, kind, detail)))
                out.append((me + "\0" + tid, None))
        return out

    # ----- the day's summaries

    def roll(self):
        """Fold spans older than the grace period into per-minute summaries,
        by then their parents and children have usually arrived."""
        cutoff = self.clock() - self.grace
        with self.lock:
            waiting = []
            for s in self.pending:
                if s.rolled:
                    continue                    # folded when it was evicted
                if s.end <= cutoff:
                    self._roll_one(s)
                else:
                    waiting.append(s)
            self.pending = waiting
            oldest = int(self.clock() - self.day) // 60 * 60
            for m in [m for m in self.minutes if m < oldest]:
                del self.minutes[m]

    def _roll_one(self, s):
        s.rolled = True
        minute = int(s.end) // 60 * 60
        bucket = self.minutes.setdefault(minute, {"nodes": {}, "edges": {}, "names": {}})
        for key, label in self._contributions(s):
            group = bucket["edges"] if "\0" in key else bucket["nodes"]
            agg = group.get(key)
            if agg is None:
                agg = group[key] = {"count": 0, "errors": 0, "hist": [0] * len(BUCKETS)}
            agg["count"] += 1
            agg["errors"] += bool(s.error)
            agg["hist"][bisect.bisect_left(BUCKETS, s.ms)] += 1
            if label:
                bucket["names"][key] = list(label)

    # ----- the map

    def snapshot(self, window):
        """The map over the last `window` seconds, as JSON-ready data. The
        same window asked again within `cache_for` seconds gets the same
        answer: drawing it over a full hour of spans takes about a second."""
        now = self.clock()
        hit = self.cache.get(window)
        if hit and 0 <= now - hit[0] < self.cache_for:
            return hit[1]
        snap = self._snapshot(window, now)
        self.cache[window] = (now, snap)
        return snap

    def _snapshot(self, window, now):
        since = now - window
        nodes, edges, labels, ops = {}, {}, {}, {}
        with self.lock:
            exact = window <= self.keep
            if exact:
                # Rates are per second of data: since this run started, or
                # since the oldest span in the window when apps sent older
                # ones (spans they buffered while Pulse was down).
                earliest = self.started
                for s in self.spans:
                    if s.end < since:
                        continue
                    earliest = min(earliest, s.end)
                    for key, label in self._contributions(s):
                        group = edges if "\0" in key else nodes
                        group.setdefault(key, Agg()).add(s.ms, s.error)
                        if label:
                            labels[key] = label
                    if s.kind in INBOUND or (not s.parent and s.kind not in OUTBOUND):
                        op = ops.setdefault(service_id(s.service), {}).setdefault(s.name, Agg())
                        op.add(s.ms, s.error)
                covered = min(window, now - earliest)
            else:
                first = None
                for minute, bucket in self.minutes.items():
                    if minute + 60 <= since:
                        continue
                    first = minute if first is None else min(first, minute)
                    for group, into in (("nodes", nodes), ("edges", edges)):
                        for key, agg in bucket[group].items():
                            into.setdefault(key, Agg(exact=False)).merge(agg)
                    labels.update({k: tuple(v) for k, v in bucket["names"].items()})
                for s in self.spans:            # not yet in a summary
                    if s.rolled or s.end < since:
                        continue
                    for key, label in self._contributions(s):
                        group = edges if "\0" in key else nodes
                        group.setdefault(key, Agg(exact=False)).add(s.ms, s.error)
                        if label:
                            labels[key] = label
                # Data starts at the earliest summary (one may come from an
                # earlier run) or when this run started, whichever is first.
                earliest = min(first, self.started) if first is not None else self.started
                covered = now - max(since, earliest)
            services = {k: dict(v, instances=len(v["instances"])) for k, v in self.services.items()}
            errors = [e for e in self.errors if e["time"] >= since]
            stats = {"spans": len(self.spans), "received": self.received, "dropped": self.dropped}

        covered = max(covered, 1.0)
        out_nodes = []
        for key in set(nodes) | {k.split("\0")[1] for k in edges} | {k.split("\0")[0] for k in edges}:
            agg = nodes.get(key)
            if key.startswith("svc:"):
                name = key[4:]
                info = services.get(name, {})
                node = {"id": key, "name": name, "kind": "service", "inferred": name not in services,
                        "detail": ", ".join(x for x in (info.get("sdk", ""), info.get("version", "")) if x),
                        "instances": info.get("instances", 0), "lastSeen": info.get("lastSeen")}
            else:
                name, kind, detail = labels.get(key, (key, "external", ""))
                node = {"id": key, "name": name, "kind": kind, "inferred": True, "detail": detail}
            node.update(_figures(agg, covered))
            node["operations"] = sorted(
                ({"name": n, **_figures(a, covered)} for n, a in ops.get(key, {}).items()),
                key=lambda o: -o["count"])[:5]
            out_nodes.append(node)
        out_edges = []
        for key, agg in edges.items():
            a, b = key.split("\0")
            out_edges.append({"from": a, "to": b, **_figures(agg, covered)})
        out_nodes.sort(key=lambda n: (n["kind"] != "service", -n["count"], n["name"]))
        out_edges.sort(key=lambda e: -e["count"])
        return {
            "window": int(window),
            "covered": int(covered),
            "exact": exact,
            "nodes": out_nodes,
            "edges": out_edges,
            "errors": list(reversed(errors))[:10],
            **stats,
        }

    # ----- keeping the day across restarts

    def save_minutes(self):
        with self.lock:
            return {str(m): b for m, b in self.minutes.items()}

    def load_minutes(self, data):
        oldest = self.clock() - self.day
        with self.lock:
            for m, b in (data or {}).items():
                try:
                    minute = int(m)
                except ValueError:
                    continue
                if minute >= oldest and isinstance(b, dict) and all(k in b for k in ("nodes", "edges", "names")):
                    ok = all(isinstance(a, dict) and len(a.get("hist", [])) == len(BUCKETS)
                             for g in ("nodes", "edges") for a in b[g].values())
                    if ok:
                        self.minutes[minute] = b


def _figures(agg, seconds):
    if agg is None:
        return {"count": 0, "rate": 0.0, "errors": 0, "errorRate": 0.0, "p95ms": None}
    p95 = agg.p95()
    return {"count": agg.count, "rate": round(agg.count / seconds, 3), "errors": agg.errors,
            "errorRate": round(agg.errors / agg.count, 4) if agg.count else 0.0,
            "p95ms": round(p95, 1) if p95 is not None else None}

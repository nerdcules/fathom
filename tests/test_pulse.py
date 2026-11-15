"""Tests for Fathom Pulse: python3 -m unittest discover -s tests"""

import gzip
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pulse")
sys.path.insert(0, ROOT)

from fathom_pulse import store  # noqa: E402

try:
    import grpc  # noqa: F401
    from opentelemetry.proto.collector.trace.v1 import trace_service_pb2
    from opentelemetry.proto.trace.v1 import trace_pb2
    from fathom_pulse import otlp
    HAVE_OTLP = True
except ImportError:
    HAVE_OTLP = False

T = "0af7651916cd43dd8448eb211c80319c"


def span(id, service, kind, start, ms, parent="", error=False, trace=T, name="op", **attrs):
    return store.Span(trace=trace, id=id, parent=parent, service=service, name=name, kind=kind,
                      start=start, end=start + ms / 1000, error=error, attrs=attrs)


class Clock:
    def __init__(self, t):
        self.t = t

    def __call__(self):
        return self.t


def nodes(snap):
    return {n["id"]: n for n in snap["nodes"]}


def edges(snap):
    return {(e["from"], e["to"]): e for e in snap["edges"]}


class Map(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(10_000.0)
        self.st = store.Store(clock=self.clock)
        self.st.started = 0

    def test_child_before_parent_still_makes_an_edge(self):
        # web's client span calls api; api's server span arrives first.
        self.st.add([span("b" * 16, "api", "server", 9990, 120, parent="a" * 16)])
        self.st.add([span("a" * 16, "web", "client", 9990, 130, parent="c" * 16),
                     span("c" * 16, "web", "server", 9989, 200)])
        snap = self.st.snapshot(900)
        e = edges(snap)[("svc:web", "svc:api")]
        self.assertEqual((e["count"], e["p95ms"]), (1, 120.0))
        # web's client span reached a service that reports itself: no
        # inferred node for it.
        self.assertEqual(sorted(nodes(snap)), ["svc:api", "svc:web"])

    def test_database_call_becomes_an_inferred_node(self):
        self.st.add([span("c" * 16, "api", "server", 9990, 50),
                     span("d" * 16, "api", "client", 9990, 12, parent="c" * 16,
                          **{"db.system": "postgresql", "server.address": "localhost", "server.port": 5432})])
        snap = self.st.snapshot(900)
        db = nodes(snap)["db:postgresql@localhost:5432"]
        self.assertEqual((db["name"], db["kind"], db["inferred"], db["detail"]),
                         ("postgresql", "database", True, "localhost:5432"))
        self.assertIn(("svc:api", "db:postgresql@localhost:5432"), edges(snap))

    def test_child_in_the_same_service_does_not_hide_the_target(self):
        self.st.add([span("e" * 16, "api", "internal", 9990, 5, parent="d" * 16),
                     span("d" * 16, "api", "client", 9990, 12, **{"url.full": "http://localhost:11434/api/chat"})])
        n = nodes(self.st.snapshot(900))["net:localhost:11434"]
        self.assertEqual((n["name"], n["kind"]), ("ollama", "ai"))

    def test_children_in_two_services(self):
        # One child in the caller's own service, one in another: the call
        # reached a service that reports itself, so no inferred node.
        self.st.add([span("e" * 16, "web", "internal", 9990, 5, parent="d" * 16),
                     span("f" * 16, "api", "server", 9990, 5, parent="d" * 16),
                     span("d" * 16, "web", "client", 9990, 12, **{"server.address": "api", "server.port": 8080})])
        snap = self.st.snapshot(900)
        self.assertEqual(sorted(nodes(snap)), ["svc:api", "svc:web"])
        self.assertIn(("svc:web", "svc:api"), edges(snap))

    def test_rate_errors_and_p95(self):
        spans = [span(f"{i:016x}", "api", "server", 9900 + i, ms=i + 1, error=(i % 10 == 0), trace=f"{i:032x}")
                 for i in range(100)]
        self.st.add(spans)
        api = nodes(self.st.snapshot(900))["svc:api"]
        self.assertEqual((api["count"], api["errors"], api["errorRate"], api["p95ms"]), (100, 10, 0.1, 95.0))
        self.assertEqual(api["rate"], round(100 / 900, 3))
        self.assertEqual(api["operations"][0]["name"], "op")

    def test_rate_counts_only_the_time_pulse_has_been_running(self):
        self.st.started = self.clock.t - 60
        self.st.add([span("a" * 16, "api", "server", 9990, 5)])
        self.assertEqual(nodes(self.st.snapshot(900))["svc:api"]["rate"], round(1 / 60, 3))

    def test_spans_older_than_this_run_count_toward_the_rate(self):
        # Pulse started a minute ago; an app sends spans from 10 minutes ago.
        self.st.started = self.clock.t - 60
        self.st.add([span(f"{i:016x}", "api", "server", self.clock.t - 600 + i, 5, trace=f"{i:032x}") for i in range(10)])
        self.assertEqual(nodes(self.st.snapshot(900))["svc:api"]["rate"], round(10 / 600, 3))

    def test_old_spans_leave_the_window(self):
        self.st.add([span("a" * 16, "api", "server", 9000, 5)])
        self.assertEqual(self.st.snapshot(900)["nodes"], [])

    def test_day_comes_from_minute_summaries(self):
        self.st.add([span(f"{i:016x}", "api", "server", 9000 + i, 100, trace=f"{i:032x}") for i in range(20)])
        self.clock.t = 9000 + 3600 + 600      # the spans are gone from memory
        self.st._evict(self.clock.t)
        self.assertEqual(len(self.st.spans), 0)
        snap = self.st.snapshot(86400)
        api = nodes(snap)["svc:api"]
        self.assertFalse(snap["exact"])
        self.assertEqual(api["count"], 20)
        # 100 ms falls in the bucket whose upper edge is the next one up.
        self.assertTrue(100 <= api["p95ms"] <= 125, api["p95ms"])

    def test_summaries_survive_a_restart(self):
        self.st.add([span("a" * 16, "api", "server", 9000, 5)])
        self.clock.t = 9500
        self.st.roll()
        saved = json.loads(json.dumps(self.st.save_minutes()))
        fresh = store.Store(clock=self.clock)
        fresh.load_minutes(saved)
        fresh.load_minutes({"x": 1, "123": {"nodes": {"svc:a": {"count": 1, "errors": 0, "hist": [1]}},
                                            "edges": {}, "names": {}}})   # bad: ignored
        self.assertEqual(nodes(fresh.snapshot(86400))["svc:api"]["count"], 1)

    def test_too_many_spans_drops_the_oldest(self):
        st = store.Store(max_spans=10, clock=self.clock)
        st.add([span(f"{i:016x}", "api", "server", 9990, 1, trace=f"{i:032x}") for i in range(15)])
        self.assertEqual((len(st.spans), st.dropped), (10, 5))

    def test_duplicates_are_counted_once(self):
        s = span("a" * 16, "api", "server", 9990, 5)
        self.st.add([s])
        self.st.add([span("a" * 16, "api", "server", 9990, 5)])
        self.assertEqual(nodes(self.st.snapshot(900))["svc:api"]["count"], 1)


class Text(unittest.TestCase):
    def test_clean_makes_one_short_line(self):
        self.assertEqual(store.clean("a\nb\x00c‮ d"), "a b c d")
        self.assertEqual(len(store.clean("x" * 500)), store.MAX_TEXT)

    def test_targets(self):
        t = lambda **a: store.target(span("a" * 16, "s", "client", 0, 1, **a))  # noqa: E731
        self.assertEqual(t(**{"peer.service": "billing"})[:3], ("svc:billing", "billing", "service"))
        self.assertEqual(t(**{"url.full": "https://api.example.com/v1/x"})[0], "net:api.example.com:443")
        self.assertEqual(t(**{"url.full": "http://[::1]:6333/collections"})[1], "qdrant")
        self.assertEqual(t(**{"messaging.system": "rabbitmq", "server.address": "mq"})[0], "mq:rabbitmq@mq")
        self.assertIsNone(t())


@unittest.skipUnless(HAVE_OTLP, "needs python-opentelemetry-proto and python-grpcio")
class Decode(unittest.TestCase):
    def request(self):
        req = trace_service_pb2.ExportTraceServiceRequest()
        rs = req.resource_spans.add()
        for k, v in (("service.name", "api\n"), ("service.version", "1.2"), ("telemetry.sdk.language", "dotnet")):
            kv = rs.resource.attributes.add()
            kv.key, kv.value.string_value = k, v
        sp = rs.scope_spans.add().spans.add()
        sp.trace_id, sp.span_id = bytes.fromhex(T), bytes.fromhex("b" * 16)
        sp.parent_span_id = bytes.fromhex("a" * 16)
        sp.name, sp.kind = "GET /orders", trace_pb2.Span.SPAN_KIND_SERVER
        sp.start_time_unix_nano, sp.end_time_unix_nano = 1_000_000_000, 1_120_000_000
        sp.status.code = trace_pb2.Status.STATUS_CODE_ERROR
        for k, v in (("http.route", "/orders"), ("ignored.attr", "x")):
            kv = sp.attributes.add()
            kv.key, kv.value.string_value = k, v
        bad = rs.scope_spans[0].spans.add()          # no ids: skipped
        bad.name = "broken"
        return req

    def test_decode(self):
        [(resource, spans)] = otlp.decode(self.request())
        s = spans[0]
        self.assertEqual(len(spans), 1)
        self.assertEqual((s.service, s.trace, s.parent, s.kind, s.error), ("api", T, "a" * 16, "server", True))
        self.assertAlmostEqual(s.ms, 120.0)
        self.assertEqual(s.attrs, {"http.route": "/orders"})
        self.assertEqual(resource["telemetry.sdk.language"], "dotnet")

    def test_json_with_hex_ids(self):
        body = json.dumps({"resourceSpans": [{"resource": {"attributes": [
            {"key": "service.name", "value": {"stringValue": "web"}}]},
            "scopeSpans": [{"spans": [{"traceId": T, "spanId": "b" * 16, "name": "x", "kind": 2,
                                       "startTimeUnixNano": "1000", "endTimeUnixNano": "2000"}]}]}]})
        [(_, [s])] = otlp.decode(otlp.parse_json(body))
        self.assertEqual((s.service, s.trace, s.id), ("web", T, "b" * 16))

    def test_inflate_refuses_bombs(self):
        bomb = gzip.compress(b"\0" * (otlp.MAX_BODY + 10))
        with self.assertRaises(ValueError):
            otlp.inflate(bomb, "gzip")
        self.assertEqual(otlp.inflate(gzip.compress(b"hi"), "gzip"), b"hi")
        with self.assertRaises(ValueError):
            otlp.inflate(b"x", "br")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@unittest.skipUnless(HAVE_OTLP, "needs python-opentelemetry-proto and python-grpcio")
class EndToEnd(unittest.TestCase):
    """The real service on spare ports: send over gRPC, HTTP/protobuf and
    HTTP/JSON, read it back with `status`, and stop it."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.grpc_port, self.http_port = free_port(), free_port()
        self.env = dict(os.environ,
                        FATHOM_PULSE_SOCKET=os.path.join(self.dir.name, "pulse.sock"),
                        FATHOM_PULSE_STATE=os.path.join(self.dir.name, "pulse.json"),
                        FATHOM_PULSE_PORTS=f"{self.grpc_port},{self.http_port}",
                        FATHOM_PULSE_ADDRESSES="127.0.0.1")
        self.bin = os.path.join(ROOT, "bin", "fathom-pulse")
        self.proc = subprocess.Popen([self.bin, "serve"], env=self.env,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        deadline = time.time() + 15
        while not os.path.exists(self.env["FATHOM_PULSE_SOCKET"]):
            if time.time() > deadline or self.proc.poll() is not None:
                self.fail("service didn't start: " + (self.proc.stdout.read() if self.proc.poll() is not None else ""))
            time.sleep(0.1)

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        self.proc.stdout.close()
        self.dir.cleanup()

    def status(self):
        out = subprocess.run([self.bin, "status", "15m"], env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def request(self, service, span_id, parent=""):
        now = time.time_ns()
        req = trace_service_pb2.ExportTraceServiceRequest()
        rs = req.resource_spans.add()
        kv = rs.resource.attributes.add()
        kv.key, kv.value.string_value = "service.name", service
        sp = rs.scope_spans.add().spans.add()
        sp.trace_id, sp.span_id = bytes.fromhex(T), bytes.fromhex(span_id)
        if parent:
            sp.parent_span_id = bytes.fromhex(parent)
        sp.name, sp.kind = "call", trace_pb2.Span.SPAN_KIND_SERVER
        sp.start_time_unix_nano, sp.end_time_unix_nano = now - 50_000_000, now
        return req

    def test_three_ways_in(self):
        import grpc as g
        # gRPC, as .NET sends by default.
        with g.insecure_channel(f"127.0.0.1:{self.grpc_port}") as ch:
            export = ch.unary_unary("/opentelemetry.proto.collector.trace.v1.TraceService/Export",
                                    request_serializer=trace_service_pb2.ExportTraceServiceRequest.SerializeToString,
                                    response_deserializer=trace_service_pb2.ExportTraceServiceResponse.FromString)
            export(self.request("web", "a" * 16), timeout=10)
            # Metrics are accepted (and dropped).
            ch.unary_unary("/opentelemetry.proto.collector.metrics.v1.MetricsService/Export")(b"", timeout=10)
        # HTTP/protobuf, gzipped.
        body = gzip.compress(self.request("api", "b" * 16, parent="a" * 16).SerializeToString())
        r = urllib.request.urlopen(urllib.request.Request(
            f"http://127.0.0.1:{self.http_port}/v1/traces", data=body, method="POST",
            headers={"Content-Type": "application/x-protobuf", "Content-Encoding": "gzip"}), timeout=10)
        self.assertEqual(r.status, 200)
        # HTTP/JSON.
        now = time.time_ns()
        body = json.dumps({"resourceSpans": [{"resource": {"attributes": [
            {"key": "service.name", "value": {"stringValue": "worker"}}]},
            "scopeSpans": [{"spans": [{"traceId": T, "spanId": "c" * 16, "parentSpanId": "b" * 16, "name": "job",
                                       "kind": 5, "startTimeUnixNano": str(now - 10_000_000),
                                       "endTimeUnixNano": str(now)}]}]}]}).encode()
        r = urllib.request.urlopen(urllib.request.Request(
            f"http://127.0.0.1:{self.http_port}/v1/traces", data=body, method="POST",
            headers={"Content-Type": "application/json"}), timeout=10)
        self.assertEqual(r.status, 200)

        snap = self.status()
        self.assertTrue(snap["running"])
        self.assertEqual(sorted(n["id"] for n in snap["nodes"]), ["svc:api", "svc:web", "svc:worker"])
        self.assertEqual(sorted((e["from"], e["to"]) for e in snap["edges"]),
                         [("svc:api", "svc:worker"), ("svc:web", "svc:api")])
        self.assertIn(f"grpc 127.0.0.1:{self.grpc_port}", snap["listening"])
        self.assertEqual(snap["received"], 3)

        # Garbage is refused, not fatal.
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(urllib.request.Request(
                f"http://127.0.0.1:{self.http_port}/v1/traces", data=b"\xff\xff not protobuf", method="POST",
                headers={"Content-Type": "application/x-protobuf"}), timeout=10)
        self.assertEqual(e.exception.code, 400)
        e.exception.close()

        # Stopping saves the day's summaries.
        self.proc.send_signal(signal.SIGTERM)
        self.assertEqual(self.proc.wait(timeout=15), 0)
        with open(self.env["FATHOM_PULSE_STATE"], encoding="utf-8") as f:
            self.assertIn("minutes", json.load(f))
        self.assertFalse(os.path.exists(self.env["FATHOM_PULSE_SOCKET"]))

    def test_status_when_not_running(self):
        self.proc.kill()
        self.proc.wait()
        os.unlink(self.env["FATHOM_PULSE_SOCKET"])
        snap = self.status()
        self.assertFalse(snap["running"])


if __name__ == "__main__":
    unittest.main()

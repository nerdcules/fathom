"""OTLP in: decode exports into Pulse's spans, and the gRPC and HTTP
receivers apps send them to.

Traces are kept. Metrics and logs are accepted and dropped, so an app that
exports all three doesn't log errors about the other two.
"""

import base64
import gzip
import json
import threading
import zlib
from concurrent import futures
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import grpc
from google.protobuf import json_format
from google.protobuf.message import DecodeError
from opentelemetry.proto.collector.trace.v1 import trace_service_pb2

from . import store

MAX_BODY = 16 * 1024 * 1024        # bytes, after decompression
STATUS_ERROR = 2                   # Status.STATUS_CODE_ERROR

TRACE_SERVICE = "opentelemetry.proto.collector.trace.v1.TraceService"
DROPPED_SERVICES = ("opentelemetry.proto.collector.metrics.v1.MetricsService",
                    "opentelemetry.proto.collector.logs.v1.LogsService")
HTTP_PATHS = {"/v1/traces": "traces", "/v1/metrics": "drop", "/v1/logs": "drop"}


# ---------------------------------------------------------------- decoding

def _value(any_value):
    which = any_value.WhichOneof("value")
    if which in ("string_value", "bool_value", "int_value", "double_value"):
        return getattr(any_value, which)
    return None


def _attrs(key_values, wanted=None):
    out = {}
    for kv in key_values:
        if wanted is not None and kv.key not in wanted:
            continue
        v = _value(kv.value)
        if v is not None:
            out[kv.key] = store.clean(v, 300) if isinstance(v, str) else v
    return out


RESOURCE_WANTED = {"service.name", "service.version", "service.instance.id", "telemetry.sdk.language"}
SPAN_WANTED = set(store.WANTED)


def decode(request):
    """An ExportTraceServiceRequest as [(resource attributes, [Span])]."""
    out = []
    for rs in request.resource_spans:
        resource = _attrs(rs.resource.attributes, RESOURCE_WANTED)
        service = store.clean(resource.get("service.name") or "unknown_service", 80)
        instance = store.clean(resource.get("service.instance.id", ""), 80)
        spans = []
        for ss in rs.scope_spans:
            for sp in ss.spans:
                if len(sp.trace_id) != 16 or len(sp.span_id) != 8:
                    continue
                spans.append(store.Span(
                    trace=sp.trace_id.hex(),
                    id=sp.span_id.hex(),
                    parent=sp.parent_span_id.hex() if len(sp.parent_span_id) == 8 else "",
                    service=service,
                    instance=instance,
                    name=store.clean(sp.name or "(unnamed)", 120),
                    kind=store.KINDS.get(sp.kind, "unspecified"),
                    start=sp.start_time_unix_nano / 1e9,
                    end=max(sp.end_time_unix_nano, sp.start_time_unix_nano) / 1e9,
                    error=sp.status.code == STATUS_ERROR,
                    message=store.clean(sp.status.message, 200),
                    attrs=_attrs(sp.attributes, SPAN_WANTED),
                ))
        if spans:
            out.append((resource, spans))
    return out


def _hex_ids_to_base64(node):
    """OTLP/JSON writes trace and span ids as hex; protobuf's JSON reader
    expects base64 for bytes fields."""
    if isinstance(node, dict):
        for key in ("traceId", "spanId", "parentSpanId"):
            v = node.get(key)
            if isinstance(v, str) and v and all(c in "0123456789abcdefABCDEF" for c in v) and len(v) % 2 == 0:
                node[key] = base64.b64encode(bytes.fromhex(v)).decode()
        for v in node.values():
            _hex_ids_to_base64(v)
    elif isinstance(node, list):
        for v in node:
            _hex_ids_to_base64(v)


def parse_json(body):
    data = json.loads(body)
    _hex_ids_to_base64(data)
    request = trace_service_pb2.ExportTraceServiceRequest()
    json_format.ParseDict(data, request, ignore_unknown_fields=True)
    return request


def inflate(body, encoding):
    """gzip or deflate, refusing anything that inflates past MAX_BODY."""
    encoding = (encoding or "").strip().lower()
    if encoding in ("", "identity"):
        return body
    if encoding not in ("gzip", "deflate"):
        raise ValueError(f"unsupported Content-Encoding {encoding!r}")
    d = zlib.decompressobj(16 + zlib.MAX_WBITS if encoding == "gzip" else zlib.MAX_WBITS)
    out = d.decompress(body, MAX_BODY + 1)
    if len(out) > MAX_BODY or d.unconsumed_tail:
        raise ValueError("body too large")
    return out


# ---------------------------------------------------------------- receivers

class Receivers:
    """One gRPC and one HTTP server per address. An address that can't be
    bound (Docker not running yet, port taken) is retried by `retry()`."""

    def __init__(self, sink, addresses, grpc_port=4317, http_port=4318, log=print):
        self.sink, self.log = sink, log
        self.ports = {"grpc": grpc_port, "http": http_port}
        self.wanted = []
        self.running = {}     # (address, kind) -> (server, "address:port")
        self.problems = {}    # "kind address:port" -> reason
        for address in addresses:
            self.want(address)

    def want(self, address):
        """Listen on another address too (from the next retry)."""
        for kind, port in self.ports.items():
            if (address, kind, port) not in self.wanted:
                self.wanted.append((address, kind, port))

    def listening(self):
        return sorted(f"{kind} {where}" for (_, kind), (_, where) in self.running.items())

    def retry(self):
        for address, kind, port in self.wanted:
            if (address, kind) in self.running:
                continue
            where = _join(address, port)
            label = f"{kind} {where}"
            try:
                server = self._start_grpc(address, port) if kind == "grpc" else self._start_http(address, port)
            except (OSError, RuntimeError) as e:
                reason = store.clean(getattr(e, "strerror", None) or e, 120)
                if self.problems.get(label) != reason:
                    self.log(f"fathom-pulse: can't listen on {label}: {reason}")
                self.problems[label] = reason
                continue
            self.problems.pop(label, None)
            self.running[(address, kind)] = (server, where)
            self.log(f"fathom-pulse: listening for OTLP/{kind} on {where}")

    def stop(self):
        for (address, kind), (server, _) in self.running.items():
            if kind == "grpc":
                server.stop(grace=1)
            else:
                server.shutdown()
                server.server_close()
        self.running.clear()

    # ----- gRPC

    def _start_grpc(self, address, port):
        server = grpc.server(futures.ThreadPoolExecutor(max_workers=4), options=[
            ("grpc.max_receive_message_length", MAX_BODY),
            ("grpc.so_reuseport", 0),
        ])

        def export_traces(request, context):
            self._take(request)
            return trace_service_pb2.ExportTraceServiceResponse()

        handlers = [grpc.method_handlers_generic_handler(TRACE_SERVICE, {
            "Export": grpc.unary_unary_rpc_method_handler(
                export_traces,
                request_deserializer=trace_service_pb2.ExportTraceServiceRequest.FromString,
                response_serializer=trace_service_pb2.ExportTraceServiceResponse.SerializeToString),
        })]
        for name in DROPPED_SERVICES:
            # Raw bytes in; an empty response message is zero bytes.
            handlers.append(grpc.method_handlers_generic_handler(name, {
                "Export": grpc.unary_unary_rpc_method_handler(
                    lambda request, context: b"",
                    request_deserializer=None, response_serializer=None),
            }))
        server.add_generic_rpc_handlers(handlers)
        if server.add_insecure_port(_join(address, port)) == 0:
            raise OSError(98, "address in use or not available")
        server.start()
        return server

    # ----- HTTP

    def _start_http(self, address, port):
        receivers = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "fathom-pulse"
            sys_version = ""

            def log_message(self, *args):
                pass

            def _reply(self, code, body=b"", ctype="application/x-protobuf"):
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                what = HTTP_PATHS.get(self.path.split("?", 1)[0])
                if what is None:
                    return self._reply(404, b"not found", "text/plain")
                try:
                    length = int(self.headers.get("Content-Length") or "0")
                except ValueError:
                    return self._reply(400, b"bad Content-Length", "text/plain")
                if length <= 0 or length > MAX_BODY:
                    return self._reply(413 if length > MAX_BODY else 400, b"bad body size", "text/plain")
                body = self.rfile.read(length)
                is_json = (self.headers.get("Content-Type") or "").split(";")[0].strip() == "application/json"
                ctype = "application/json" if is_json else "application/x-protobuf"
                empty = b"{}" if is_json else b""
                if what == "drop":
                    return self._reply(200, empty, ctype)
                try:
                    body = inflate(body, self.headers.get("Content-Encoding"))
                    if is_json:
                        request = parse_json(body)
                    else:
                        request = trace_service_pb2.ExportTraceServiceRequest.FromString(body)
                except (ValueError, DecodeError, json_format.ParseError, zlib.error) as e:
                    return self._reply(400, store.clean(e, 200).encode(), "text/plain")
                receivers._take(request)
                self._reply(200, empty, ctype)

        family = 10 if ":" in address else 2       # AF_INET6 / AF_INET

        class Server(ThreadingHTTPServer):
            address_family = family
            daemon_threads = True
            allow_reuse_address = True

        server = Server((address, port), Handler)
        threading.Thread(target=server.serve_forever, name=f"http {address}", daemon=True).start()
        return server

    def _take(self, request):
        for resource, spans in decode(request):
            self.sink(spans, resource)


def _join(address, port):
    return f"[{address}]:{port}" if ":" in address else f"{address}:{port}"

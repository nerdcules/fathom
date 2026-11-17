#!/usr/bin/env python3
"""Made-up data for the promo's deck scenes, in the shapes Fathom's commands
print. Nothing here is read from this machine: the containers, projects,
devices (in the 192.0.2.0/24 documentation range) and sites (.example) are
invented. Pulse's map comes from Pulse's own Store, fed synthetic traces;
Crumbs' from crumbs/demo/make-demo.py, which runs fathom-crumbs on made-up
browser profiles.

  demo-data.py <out dir>   -> start.json apps.json deck.json care.json
                              sentinel.json pulse.json agents.json
                              crumbs-status.json crumbs-detail.json
"""

import json
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "pulse"))
from fathom_pulse import store  # noqa: E402

NOW = int(time.time())
GB = 1_000_000_000


def start():
    menu = {
        "home": "/home/demo",
        "status": {"name": "Demo User", "user": "demo", "host": "fathom-demo", "docker": "active"},
        "config": {"pinned": ["foot", "code", "fathom:deck", "fathom:care", "chromium", "org.gnome.Nautilus"],
                   "suggestions": ["Why is my build slow?", "Write tests for the API", "Explain this stack trace"]},
        "projects": [
            {"name": "orders-api", "path": "/home/demo/Work/orders-api", "branch": "main*", "tech": [".NET", "Docker"], "when": NOW - 1800},
            {"name": "storefront", "path": "/home/demo/Work/storefront", "branch": "feature/cart", "tech": ["TypeScript"], "when": NOW - 7200},
            {"name": "ml-notebooks", "path": "/home/demo/Work/ml-notebooks", "branch": "main", "tech": ["Python"], "when": NOW - 86400},
            {"name": "infra", "path": "/home/demo/Work/infra", "branch": "main", "tech": ["Terraform"], "when": NOW - 3 * 86400},
        ],
    }
    apps = [{"id": i, "name": n, "comment": c, "icon": "", "keywords": ""} for i, n, c in (
        ("foot", "Terminal", "Terminal emulator"), ("code", "Visual Studio Code", "Code editor"),
        ("chromium", "Chromium", "Web browser"), ("org.gnome.Nautilus", "Files", "File manager"),
        ("btop", "Btop", "System monitor"), ("obsidian", "Obsidian", "Notes"),
        ("lazydocker", "Lazydocker", "Docker in a terminal"), ("spotify", "Spotify", "Music"))]
    return menu, apps


def deck():
    containers = [
        ("orders-api-1", "orders", "orders-api:dev", "running", "Up 3 hours (healthy)", "0.0.0.0:8080->8080/tcp", "1.2%", "212MiB / 31GiB"),
        ("orders-db-1", "orders", "postgres:18", "running", "Up 3 hours (healthy)", "0.0.0.0:5432->5432/tcp", "0.4%", "96MiB / 31GiB"),
        ("orders-cache-1", "orders", "redis:8", "running", "Up 3 hours", "0.0.0.0:6379->6379/tcp", "0.2%", "11MiB / 31GiB"),
        ("orders-worker-1", "orders", "orders-worker:dev", "restarting", "Restarting (1) 8 seconds ago", "", "", ""),
        ("storefront-web-1", "storefront", "storefront:dev", "running", "Up 40 minutes", "0.0.0.0:5173->5173/tcp", "3.1%", "180MiB / 31GiB"),
        ("ollama", "", "ollama/ollama", "running", "Up 2 days", "127.0.0.1:11434->11434/tcp", "0.1%", "1.9GiB / 31GiB"),
    ]
    return {
        "time": NOW,
        "system": {"cpu": 14.2, "gpu": 22, "cores": 8, "memTotal": 32 * 1024 ** 3, "memUsed": int(13.4 * 1024 ** 3),
                   "uptime": 3 * 86400 + 7200, "disks": [{"mount": "/", "size": 1000 * GB, "used": 412 * GB, "free": 588 * GB}]},
        "docker": {"state": "ok", "containers": [
            {"name": n, "project": p, "image": i, "state": s, "status": st, "ports": po, "cpu": c, "mem": m}
            for n, p, i, s, st, po, c, m in containers],
            "disk": [{"type": "Images", "size": "18.2GB", "reclaimable": "5.1GB (28%)"},
                     {"type": "Containers", "size": "240MB", "reclaimable": "0B"},
                     {"type": "Local Volumes", "size": "3.4GB", "reclaimable": "1.2GB (35%)"},
                     {"type": "Build Cache", "size": "6.8GB", "reclaimable": "6.8GB"}]},
        "dotnet": {"sdks": ["10.0.100", "9.0.300"], "processes": [
            {"pid": 4101, "name": "OrdersApi", "kind": "app", "folder": "orders-api", "cpu": 2.4, "rss": 188 * 1024 ** 2},
            {"pid": 4188, "name": "dotnet watch", "kind": "watch", "folder": "orders-api", "cpu": 0.3, "rss": 96 * 1024 ** 2},
            {"pid": 4230, "name": "Orders.AppHost", "kind": "apphost", "folder": "orders-api", "cpu": 0.8, "rss": 140 * 1024 ** 2},
            {"pid": 4302, "name": "Microsoft.CodeAnalysis.LanguageServer", "kind": "tooling", "folder": "orders-api", "cpu": 0.0, "rss": 330 * 1024 ** 2}]},
        "ai": {"agents": [
            {"pid": 5001, "name": "Claude Code", "where": "terminal", "folder": "orders-api", "cpu": 3.1, "rss": 410 * 1024 ** 2, "status": "busy"},
            {"pid": 5022, "name": "Claude Code", "where": "editor", "folder": "storefront", "cpu": 0.0, "rss": 240 * 1024 ** 2, "status": "idle"}],
            "ollama": {"models": [{"name": "qwen3:8b", "vram": 6 * 1024 ** 3}]}},
    }


def care():
    return {
        "time": NOW, "checkedAt": NOW - 3600, "checking": False,
        "disk": {"model": "Demo NVMe 1TB", "size": 1000 * GB, "used": 412 * GB, "free": 588 * GB, "pct": 41.2,
                 "breakdown": {"docker": 28 * GB, "models": 9 * GB, "caches": 21 * GB, "projects": 34 * GB, "home": 96 * GB},
                 "forecastDays": None},
        "info": {"battery": 86, "cycles": 212, "cpuTemp": 54, "lastUpdate": NOW - 2 * 86400, "snapshots": True},
        "reclaim": [{"id": "nuget", "bytes": int(6.2 * GB), "root": False},
                    {"id": "docker-images", "bytes": int(5.1 * GB), "root": False},
                    {"id": "journal", "bytes": int(1.8 * GB), "root": True}],
        "updates": {"packages": [{"name": "firefox", "from": "145.0-1", "to": "145.0.1-1"},
                                 {"name": "docker", "from": "28.5.1-1", "to": "28.5.2-1"},
                                 {"name": "dotnet-sdk", "from": "10.0.100-1", "to": "10.0.101-1"}],
                    "aur": [], "kernel": False, "omarchy": None, "download": 214_000_000, "firmware": 0, "restart": False},
        "warnings": [{"kind": "unit", "scope": "user", "unit": "orders-sync.service",
                      "description": "Orders nightly sync"}],
    }


def sentinel():
    devices = [
        ("192.0.2.1", "Demo Router Co.", True, True), ("192.0.2.20", "Phone maker", True, False),
        ("192.0.2.31", "TV maker", True, False), ("192.0.2.44", "Printer maker", True, False),
        ("192.0.2.57", None, False, False)]
    return {
        "time": NOW, "attention": 1, "watching": True, "rootParts": True,
        "firewall": {"on": True, "lockdown": False, "blocked": []},
        "integrity": {"checkedAt": NOW - 5 * 3600, "files": 361204, "packages": 1150, "altered": 0},
        "opensnitch": {"installed": True, "active": True, "rules": 14, "allow": 12, "deny": 2, "recent": []},
        "blocksToday": {"total": 37, "top": [{"src": "198.51.100.23", "count": 21, "public": True},
                                             {"src": "203.0.113.9", "count": 9, "public": True}]},
        "events": [
            {"id": "dev-1", "time": NOW - 900, "kind": "device", "level": "warn", "title": "New device on DemoNet",
             "detail": "192.0.2.57, maker unknown", "data": {}},
            {"id": "usb-1", "time": NOW - 4 * 3600, "kind": "usb", "level": "info", "title": "USB storage plugged in",
             "detail": "Demo 64 GB stick", "data": {}},
            {"id": "sudo-1", "time": NOW - 5 * 3600, "kind": "sudo", "level": "info", "title": "sudo: pacman -Syu",
             "detail": "by demo", "data": {}}],
        "network": {"ssid": "DemoNet", "gateway": "192.0.2.1", "devices": [
            {"ip": ip, "mac": f"02:00:5e:00:00:{i:02x}", "vendor": v, "trusted": t, "gateway": g,
             "first": NOW - (30 - i) * 86400 if t else NOW - 900, "last": NOW - 60}
            for i, (ip, v, t, g) in enumerate(devices, 1)]},
    }


def pulse():
    rnd = random.Random(7)
    st = store.Store()
    st.started = NOW - 3600
    t0 = NOW - 600
    n = 0
    spans = []

    def sid():
        nonlocal n
        n += 1
        return f"{n:016x}"

    for i in range(400):
        trace = f"{i:032x}"
        t = t0 + i * 1.4
        web, web_c, api = sid(), sid(), sid()
        spans.append(store.Span(trace, web, "", "storefront", "GET /cart", "server", t, t + 0.18))
        spans.append(store.Span(trace, web_c, web, "storefront", "GET /orders", "client", t + 0.01, t + 0.16,
                                attrs={"peer.service": "orders-api"}))
        slow = rnd.random() < 0.04
        err = rnd.random() < 0.02
        spans.append(store.Span(trace, api, web_c, "orders-api", "GET /orders", "server", t + 0.02,
                                t + (0.9 if slow else 0.14), error=err, message="timeout" if err else ""))
        spans.append(store.Span(trace, sid(), api, "orders-api", "SELECT orders", "client", t + 0.03, t + 0.05,
                                attrs={"db.system": "postgresql", "server.address": "orders-db", "server.port": 5432}))
        spans.append(store.Span(trace, sid(), api, "orders-api", "GET cart", "client", t + 0.025, t + 0.027,
                                attrs={"db.system": "redis", "server.address": "orders-cache", "server.port": 6379}))
        if i % 5 == 0:
            spans.append(store.Span(trace, sid(), api, "orders-api", "publish order", "producer", t + 0.06, t + 0.065,
                                    attrs={"messaging.system": "rabbitmq", "server.address": "mq", "server.port": 5672}))
        if i % 8 == 0:
            spans.append(store.Span(trace, sid(), api, "orders-api", "chat", "client", t + 0.07, t + 0.6,
                                    attrs={"gen_ai.provider.name": "ollama", "server.address": "localhost", "server.port": 11434}))
    st.add(spans)
    snap = st.snapshot(900)
    snap.update(running=True, time=NOW, listening=["127.0.0.1:4317", "127.0.0.1:4318"], problems=[],
                ports={"grpc": 4317, "http": 4318}, range="15m")
    return snap


def agents():
    day_start = NOW - NOW % 86400
    def spans(first, pattern):
        out, t = [], first
        for work, wait in pattern:
            out.append([t, t + work, "working"])
            t += work + wait
        return out
    projects = []
    for i, (name, first, pattern, state) in enumerate((
            ("orders-api", NOW - 5 * 3600, [(900, 300), (1500, 600), (600, 120), (1200, 0)], "working"),
            ("storefront", NOW - 3 * 3600, [(600, 900), (300, 1200)], "idle"))):
        sp = spans(first, pattern)
        projects.append({
            "id": f"p{i}", "name": name, "path": f"/home/demo/Work/{name}", "state": state,
            "first": first, "last": sp[-1][1], "prompts": 6 - 3 * i, "commands": 140 - 90 * i, "edits": 31 - 20 * i,
            "files": 12 - 7 * i, "tests": 48 - 40 * i, "outputTokens": 152_000 - 110_000 * i,
            "working": sum(s[1] - s[0] for s in sp), "waiting": 600, "waitingSince": None, "spans": sp,
            "sessions": [{"title": "Add order cancellation" if i == 0 else "Cart page polish", "branch": "main",
                          "model": "claude-opus-5-5", "open": i == 0, "prompts": 6 - 3 * i, "since": sp[-1][0],
                          "start": first, "end": sp[-1][1], "state": state, "waiting": 600,
                          "working": sum(s[1] - s[0] for s in sp)}]})
    return {"agent": "Claude Code", "day": time.strftime("%Y-%m-%d", time.gmtime(NOW)), "found": True,
            "idleAfter": 600, "open": 1, "start": day_start, "time": NOW,
            "read": {"files": 2, "bytes": 90000, "ms": 4}, "projects": projects}


def main(out):
    os.makedirs(out, exist_ok=True)
    menu, apps = start()
    files = {"start.json": menu, "apps.json": apps, "deck.json": deck(), "care.json": care(),
             "sentinel.json": sentinel(), "pulse.json": pulse(), "agents.json": agents()}
    for name, data in files.items():
        with open(os.path.join(out, name), "w") as f:
            json.dump(data, f)
    crumbs = os.path.join(out, "crumbs")
    subprocess.run([os.path.join(REPO, "crumbs", "demo", "make-demo.py"), crumbs], check=True)
    os.replace(os.path.join(crumbs, "status.json"), os.path.join(out, "crumbs-status.json"))
    os.replace(os.path.join(crumbs, "detail.json"), os.path.join(out, "crumbs-detail.json"))
    os.rmdir(crumbs)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip())
    main(sys.argv[1])

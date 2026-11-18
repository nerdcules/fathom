#!/usr/bin/env python3
"""Drive the test VM through QEMU's QMP socket (run.sh opens it as $FATHOM_VM/qmp.sock).

  qmp.py SOCK shot FILE.ppm      a screenshot of the VM's screen (PPM)
  qmp.py SOCK unlock LAYOUT      wait for the disk's passphrase prompt, then type
                                 the passphrase read from stdin, and Enter, once
  qmp.py SOCK type LAYOUT        type a line read from stdin, and Enter, now

LAYOUT is the VM's keyboard layout at the prompt, uk or us: QMP sends keys, not
characters, and # and ~ are on different keys in the two. Letters, digits and
those two are all it can type.

unlock types once. If the passphrase is wrong the VM asks again and this exits
1, so a wrong passphrase in a file never uses up systemd's tries by itself.
"""
import json
import socket
import sys
import tempfile
import time
from pathlib import Path

SPECIAL = {
    "uk": {"#": ("backslash", False), "~": ("backslash", True)},
    "us": {"#": ("3", True), "~": ("grave_accent", True)},
}


class QMP:
    def __init__(self, path, wait=60):
        deadline = time.monotonic() + wait
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.connect(path)
                break
            except OSError:
                self.sock.close()
                if time.monotonic() > deadline:
                    raise
                time.sleep(1)
        self.f = self.sock.makefile("rw")
        self.f.readline()  # the greeting
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        self.f.write(json.dumps(msg) + "\n")
        self.f.flush()
        while True:
            reply = json.loads(self.f.readline())
            if "error" in reply:
                raise RuntimeError(f"{name}: {reply['error']}")
            if "return" in reply:
                return reply["return"]

    def key(self, qcode, down):
        self.cmd("input-send-event", events=[
            {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": qcode}}}])
        time.sleep(0.05)

    def tap(self, qcode, shift=False):
        if shift:
            self.key("shift", True)
        self.key(qcode, True)
        self.key(qcode, False)
        if shift:
            self.key("shift", False)

    def type_line(self, text, layout):
        special = SPECIAL[layout]
        for ch in text:
            if ch not in special and not (ch.isascii() and ch.isalnum()):
                raise ValueError("qmp.py can type only letters, digits, # and ~")
        for ch in text:
            if ch in special:
                self.tap(*special[ch])
            else:
                self.tap(ch.lower(), ch.isupper())
        self.tap("ret")

    def screen(self):
        """The screen as (width, height, rows of bytes, 3 bytes a pixel), or
        (0, 0, []) before the VM has drawn one ("no surface", seen in the GTK
        window before the firmware starts)."""
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "s.ppm"
            try:
                self.cmd("screendump", filename=str(p))
            except RuntimeError as e:
                if "no surface" in str(e):
                    return 0, 0, []
                raise
            data = p.read_bytes()
        # P6 header: magic, width, height, maxval, then one whitespace byte.
        fields, pos = [], 0
        while len(fields) < 4:
            while data[pos:pos + 1].isspace():
                pos += 1
            start = pos
            while not data[pos:pos + 1].isspace():
                pos += 1
            fields.append(data[start:pos])
        w, h = int(fields[1]), int(fields[2])
        px = data[pos + 1:]
        return w, h, [px[y * w * 3:(y + 1) * w * 3] for y in range(h)]


def bright(row):
    return sum(1 for i in range(0, len(row), 3) if max(row[i:i + 3]) > 128)


def at_prompt(qmp):
    """The passphrase prompt alone: text on the first line of an otherwise black
    screen (systemd's text prompt, as on 18 November 2026, 1280x800). A wrong try
    adds lines below it, so this is false again after one."""
    w, h, rows = qmp.screen()
    top = sum(bright(r) for r in rows[:32])
    rest = sum(bright(r) for r in rows[48:])
    return top > 50 and rest == 0, f"{w}x{h} top={top} rest={rest}"


def asked_again(qmp):
    """After a wrong try: the prompt (rows 16-31), "No key available with this
    passphrase." (32-47), a blank line, the prompt again (64-79), and black below."""
    w, h, rows = qmp.screen()
    lit = [sum(bright(r) for r in rows[y:y + 16]) for y in (16, 32, 48, 64)]
    below = sum(bright(r) for r in rows[80:])
    return lit[0] > 50 and lit[1] > 50 and lit[2] == 0 and lit[3] > 50 and below == 0


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    sock, action = argv[1], argv[2]
    qmp = QMP(sock)
    if action == "shot":
        w, h, rows = qmp.screen()
        if not rows:
            sys.exit("qmp.py: the VM hasn't drawn a screen yet")
        Path(argv[3]).write_bytes(b"P6\n%d %d\n255\n" % (w, h) + b"".join(rows))
        return 0
    layout = argv[3] if len(argv) > 3 else "us"
    if layout not in SPECIAL:
        sys.exit(f"qmp.py: layout is uk or us, not {layout}")
    text = sys.stdin.readline().rstrip("\n")
    if action == "type":
        qmp.type_line(text, layout)
        return 0
    if action != "unlock":
        sys.exit(__doc__)
    start, seen = time.monotonic(), None
    while time.monotonic() - start < 300:
        ok, how = at_prompt(qmp)
        if how != seen:  # what the screen looks like, each time it changes
            print(f"qmp.py: {time.monotonic() - start:.0f} s: {how}", flush=True)
            seen = how
        if ok:
            # Twice in a row, 2 s apart, so it isn't a frame on the way past.
            time.sleep(2)
            ok, how = at_prompt(qmp)
        if ok:
            print(f"qmp.py: prompt at {time.monotonic() - start:.0f} s ({how}); typing", flush=True)
            qmp.type_line(text, layout)
            time.sleep(10)
            if asked_again(qmp):
                print("qmp.py: the VM asked again: wrong passphrase or layout; type it yourself", flush=True)
                return 1
            print("qmp.py: typed; the VM didn't ask again", flush=True)
            return 0
        time.sleep(2)
    print("qmp.py: no passphrase prompt within 300 s; nothing typed", flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

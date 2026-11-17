"""A sandbox for running install.sh and uninstall.sh in tests.

HOME and every XDG folder are in a scratch folder, and the environment is
built from nothing, so there is no session bus, Hyprland socket or display
to reach. PATH holds only stand-ins and a short list of file tools: every
command that could change the machine (omarchy, hyprctl, systemctl, sudo,
pkexec, ufw, ...) is a stand-in that records its arguments and changes
nothing, so sudo and pkexec never run what they are given.

STUB_FAIL lists shell patterns, one per line; a call matching one, as
"name arg arg...", fails.
"""

import os
import shutil
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Real tools the scripts may use: they only read and write files.
TOOLS = ("bash", "sh", "env", "python3", "jq", "od", "tr", "cp", "rm", "mkdir", "ln", "sed", "grep", "find",
         "chmod", "mv", "date", "dirname", "basename", "tail", "head", "wc", "cat", "sleep", "touch",
         "readlink", "realpath", "mktemp", "sort", "uniq", "cmp", "diff", "ls", "printf", "true", "false",
         "stat", "id", "rmdir", "tee", "cut")

# Stand-ins: they record the call and do nothing else (see STUB below).
STUBS = ("omarchy", "omarchy-shell", "omarchy-restart-shell", "hyprctl", "systemctl", "sudo", "pkexec",
         "ufw", "ip", "mpv", "yt-dlp", "socat", "wl-paste", "curl", "nmcli", "secret-tool", "busctl",
         "xdg-open", "iw", "pgrep", "setsid", "uwsm-app")

STUB = r'''#!/usr/bin/python3 -I
import fnmatch, json, os, sys
name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
state = os.environ["STUB_STATE"]
line = " ".join([name] + args)
with open(os.path.join(state, "calls.log"), "a") as f:
    f.write(line + "\n")
for pat in filter(None, os.environ.get("STUB_FAIL", "").split("\n")):
    if fnmatch.fnmatchcase(line, pat):
        sys.exit(f"{name}: told to fail")

def read(key, default=""):
    try:
        with open(os.path.join(state, key)) as f:
            return f.read().strip()
    except FileNotFoundError:
        return default

def write(key, value):
    with open(os.path.join(state, key), "w") as f:
        f.write(value + "\n")

if name == "omarchy":
    if args[:2] == ["theme", "current"]:
        print(read("theme", "Tokyo Night"))
    elif args[:2] == ["theme", "set"]:
        write("theme", args[2])
    elif args[:2] == ["bar", "background"]:
        if len(args) == 2:
            print(read("bar", "opaque"))
        else:
            write("bar", args[2])
    elif args[:2] == ["plugin", "validate"]:
        if not os.path.isfile(os.path.join(args[2], "manifest.json")):
            sys.exit("omarchy: no manifest.json")
elif name == "ip" and "docker0" in args and os.environ.get("STUB_DOCKER0"):
    print(json.dumps([{"addr_info": [{"local": os.environ["STUB_DOCKER0"]}]}]))
'''


class Sandbox:
    def __init__(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        self.config = os.path.join(self.home, ".config")
        self.data = os.path.join(self.home, ".local", "share")
        self.state = os.path.join(self.home, ".local", "state")
        self.stub_state = os.path.join(self.tmp, "stub")
        self.bin = os.path.join(self.tmp, "bin")
        for d in (self.config, self.data, self.state, self.stub_state, self.bin,
                  os.path.join(self.tmp, "run"), os.path.join(self.config, "hypr")):
            os.makedirs(d, exist_ok=True)
        with open(os.path.join(self.config, "hypr", "hyprland.lua"), "w") as f:
            f.write("-- the user's own Hyprland file\nrequire(\"omarchy\")\n")
        for tool in TOOLS:
            real = shutil.which(tool, path="/usr/bin:/bin")
            if real:
                os.symlink(real, os.path.join(self.bin, tool))
        for name in STUBS:
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(STUB)
            os.chmod(path, 0o755)
        self.env = {
            "HOME": self.home, "PATH": self.bin, "LANG": "C.UTF-8",
            "XDG_CONFIG_HOME": self.config, "XDG_DATA_HOME": self.data, "XDG_STATE_HOME": self.state,
            "XDG_RUNTIME_DIR": os.path.join(self.tmp, "run"), "STUB_STATE": self.stub_state,
            "FATHOM_UFW_DIR": os.path.join(self.tmp, "ufw"),
        }

    def cleanup(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run(self, script, *args, fail=(), **env):
        e = dict(self.env, **env)
        if fail:
            e["STUB_FAIL"] = "\n".join(fail)
        return subprocess.run(["bash", os.path.join(REPO, script), *args], env=e, cwd=self.tmp,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=300)

    def calls(self):
        try:
            with open(os.path.join(self.stub_state, "calls.log")) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def clear_calls(self):
        try:
            os.remove(os.path.join(self.stub_state, "calls.log"))
        except FileNotFoundError:
            pass

    def path(self, *parts):
        return os.path.join(self.home, *parts)

    def snapshot(self):
        """Every file and link under HOME, with its content or target."""
        out = {}
        for root, dirs, files in os.walk(self.home):
            for name in dirs + files:
                p = os.path.join(root, name)
                rel = os.path.relpath(p, self.home)
                if os.path.islink(p):
                    out[rel] = "-> " + os.readlink(p)
                    if name in dirs:
                        dirs.remove(name)
                elif os.path.isfile(p):
                    with open(p, "rb") as f:
                        out[rel] = f.read()
        return out

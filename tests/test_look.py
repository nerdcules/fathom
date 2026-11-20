"""fathom-look, run against a scratch home with stand-ins for omarchy and
hyprctl: Fathom's own look rebuilds theme/ unchanged, a changed look
rewrites only what it should, bad values change nothing, a theme folder the
user made is left alone, and the theme refreshes only when Fathom is on."""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOOK = os.path.join(REPO, "look", "bin", "fathom-look")
THEME = os.path.join(REPO, "theme")
GENERATED = ("colors.toml", "shell.toml", "hyprland.lua")

# Logs each call; `theme current` answers $THEME_NOW, `bar background` $BAR_NOW.
OMARCHY = """echo "$*" >> "$CALLS"
case "$*" in
  "theme current") echo "${THEME_NOW:-Fathom}" ;;
  "bar background") echo "${BAR_NOW:-glassy}" ;;
  "theme refresh") exit "${REFRESH_EXIT:-0}" ;;
esac
"""
HYPRCTL = """echo '{"option":"decoration:blur:enabled","bool":true,"set":true}'
"""


def read(path):
    with open(path) as f:
        return f.read()


class LookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.cfg = os.path.join(self.tmp, "config")
        self.data = os.path.join(self.tmp, "data")
        self.state = os.path.join(self.tmp, "state")
        bin_dir = os.path.join(self.tmp, "bin")
        os.makedirs(bin_dir)
        for name, script in (("omarchy", OMARCHY), ("hyprctl", HYPRCTL)):
            path = os.path.join(bin_dir, name)
            with open(path, "w") as f:
                f.write("#!/bin/sh\n" + script)
            os.chmod(path, 0o755)
        os.makedirs(os.path.join(self.data, "fathom"))
        os.symlink(THEME, os.path.join(self.data, "fathom", "theme"))
        self.calls = os.path.join(self.tmp, "calls")
        self.env = dict(os.environ, XDG_CONFIG_HOME=self.cfg, XDG_DATA_HOME=self.data,
                        XDG_STATE_HOME=self.state, CALLS=self.calls,
                        PATH=bin_dir + os.pathsep + os.environ["PATH"])
        self.theme_dir = os.path.join(self.cfg, "omarchy", "themes", "fathom")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def look(self, *args, **env):
        return subprocess.run([LOOK, *args], capture_output=True, text=True,
                              env=dict(self.env, **env), timeout=30)

    def built(self, name):
        return read(os.path.join(self.theme_dir, name))

    def omarchy_calls(self):
        return read(self.calls).splitlines() if os.path.exists(self.calls) else []

    def test_fathoms_own_look_rebuilds_the_theme_unchanged(self):
        r = self.look("build")
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in sorted(os.listdir(THEME)):
            src, dest = os.path.join(THEME, name), os.path.join(self.theme_dir, name)
            self.assertFalse(os.path.islink(dest), name)
            if os.path.isfile(src):
                with open(src, "rb") as a, open(dest, "rb") as b:
                    self.assertEqual(a.read(), b.read(), name)
        self.assertTrue(os.path.exists(os.path.join(self.theme_dir, ".fathom-install")))

    def test_a_changed_look_rewrites_colours_corners_and_panels(self):
        r = self.look("set", "accent", "#FF6B81", "frame", "#3ddc97", "corners", "8",
                      "opacity", "75", "glow", "off")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(read(os.path.join(self.cfg, "fathom", "look.json"))),
                         {"accent": "#ff6b81", "frame": "#3ddc97", "frameStyle": "gradient",
                          "corners": 8, "opacity": 75, "glow": False})
        colors, shell, hypr = (self.built(n) for n in GENERATED)
        self.assertIn('accent = "#ff6b81"', colors)
        self.assertIn('hyprland_active_border = "rgba(ff6b81ee) rgba(3ddc97ee) 45deg"', colors)
        # The palette's cyan stays: only the accent changes.
        self.assertIn('cyan = "#4cc9f0"', colors)
        self.assertNotIn("4cc9f0", shell.lower())
        self.assertIn('active-border            = "rgba(ff6b81ee) rgba(3ddc97ee) 45deg"', shell)
        self.assertEqual(shell.count("background-alpha = 0.75"), 1)          # notifications
        self.assertEqual(shell.count("background-alpha = 1.0"), 2)           # bar flyouts and tooltips stay solid
        self.assertEqual(shell.count("background-alpha          = 0.75"), 2)  # launcher, menu
        self.assertIn("background-alpha = 0.6", shell)                       # the bar keeps its own
        self.assertIn("background-alpha = 0.95", shell)                      # and the password prompt
        self.assertIn('{ colors = { "rgba(ff6b81ee)", "rgba(3ddc97ee)" }, angle = 45 }', hypr)
        self.assertIn("rounding = 8,", hypr)
        # Everything else is as shipped.
        for name in set(os.listdir(THEME)) - set(GENERATED):
            if os.path.isfile(os.path.join(THEME, name)):
                with open(os.path.join(THEME, name), "rb") as a, open(os.path.join(self.theme_dir, name), "rb") as b:
                    self.assertEqual(a.read(), b.read(), name)

    def test_a_solid_frame_is_one_colour(self):
        self.assertEqual(self.look("set", "frame-style", "solid", "opacity", "100").returncode, 0)
        self.assertIn('local active_border_color = "rgba(4cc9f0ee)"', self.built("hyprland.lua"))
        self.assertIn('hyprland_active_border = "rgba(4cc9f0ee)"', self.built("colors.toml"))
        self.assertIn("background-alpha = 1.0", self.built("shell.toml"))

    def test_the_built_hyprland_file_is_valid_lua(self):
        if not shutil.which("luac"):
            self.skipTest("luac not installed")
        for args in (("build",), ("set", "frame-style", "solid", "corners", "0")):
            self.assertEqual(self.look(*args).returncode, 0)
            r = subprocess.run(["luac", "-p", os.path.join(self.theme_dir, "hyprland.lua")],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_bad_values_change_nothing(self):
        self.assertEqual(self.look("set", "corners", "12").returncode, 0)
        before = read(os.path.join(self.cfg, "fathom", "look.json"))
        for args in (("corners", "31"), ("opacity", "59"), ("accent", "red"), ("accent", "#12345"),
                     ("glow", "yes"), ("frame-style", "dots"), ("size", "3"), ("corners",),
                     ("corners", "12", "accent", "nope")):
            r = self.look("set", *args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("fathom-look:", r.stderr)
        self.assertEqual(read(os.path.join(self.cfg, "fathom", "look.json")), before)
        self.assertIn("rounding = 12,", self.built("hyprland.lua"))

    def test_an_unreadable_look_file_is_fathoms_own(self):
        os.makedirs(os.path.join(self.cfg, "fathom"))
        with open(os.path.join(self.cfg, "fathom", "look.json"), "w") as f:
            f.write('{"accent": "#zzzzzz", "corners": 500, "glow": "maybe"')
        state = json.loads(self.look("state").stdout)
        self.assertEqual(state["look"], state["defaults"])

    def test_a_theme_folder_the_user_made_is_left_alone(self):
        os.makedirs(self.theme_dir)
        with open(os.path.join(self.theme_dir, "colors.toml"), "w") as f:
            f.write("mine\n")
        r = self.look("build")
        self.assertEqual(r.returncode, 1)
        self.assertIn("wasn't made by Fathom", r.stderr)
        self.assertEqual(read(os.path.join(self.theme_dir, "colors.toml")), "mine\n")

    def test_an_older_install_link_is_replaced_by_a_built_folder(self):
        os.makedirs(os.path.dirname(self.theme_dir))
        os.symlink(THEME, self.theme_dir)
        self.assertEqual(self.look("set", "corners", "4").returncode, 0)
        self.assertFalse(os.path.islink(self.theme_dir))
        # The repo's own theme isn't touched through the old link.
        self.assertIn("rounding = 22,", read(os.path.join(THEME, "hyprland.lua")))

    def test_it_refreshes_the_theme_only_when_fathom_is_on(self):
        self.assertEqual(self.look("set", "corners", "4").returncode, 0)
        self.assertIn("theme refresh", self.omarchy_calls())
        os.remove(self.calls)
        r = self.look("set", "corners", "6", THEME_NOW="Tokyo Night")
        self.assertEqual(r.returncode, 0)
        self.assertIn("Saved", r.stdout)
        self.assertNotIn("theme refresh", self.omarchy_calls())

    def test_a_failed_refresh_is_reported(self):
        r = self.look("apply", REFRESH_EXIT="3")
        self.assertEqual(r.returncode, 1)
        self.assertIn("omarchy theme refresh failed", r.stderr)

    def test_state_lists_the_bar_blur_and_wallpapers(self):
        bg = os.path.join(self.state, "omarchy", "current", "theme", "backgrounds")
        os.makedirs(bg)
        for name in ("1-horizon.webp", "2-eclipse.webp", "notes.txt"):
            open(os.path.join(bg, name), "w").close()
        os.symlink(os.path.join(bg, "2-eclipse.webp"), os.path.join(self.state, "omarchy", "current", "background"))
        state = json.loads(self.look("state", BAR_NOW="none").stdout)
        self.assertEqual(state["bar"], "none")
        self.assertIs(state["blur"], True)
        self.assertTrue(state["fathomOn"])
        self.assertEqual([w["name"] for w in state["wallpapers"]], ["Horizon", "Eclipse"])
        self.assertEqual(state["wallpaper"], os.path.join(bg, "2-eclipse.webp"))

    def test_bar_and_wallpaper_go_to_omarchy(self):
        pic = os.path.join(self.tmp, "pic.png")
        open(pic, "w").close()
        self.assertEqual(self.look("bar", "opaque").returncode, 0)
        self.assertEqual(self.look("wallpaper", pic).returncode, 0)
        self.assertEqual(self.look("bar", "frosted").returncode, 1)
        self.assertEqual(self.look("wallpaper", os.path.join(self.tmp, "missing.png")).returncode, 1)
        self.assertEqual(self.omarchy_calls(), ["bar background opaque", f"theme bg set {pic}"])


# Stand-ins for Omarchy's screensaver plumbing, logging to $CALLS. The
# shell-config one keeps the real helper's interface: source it, then
# commit '<jq program>' [jq args], with $NORMALIZE, writing ~/.config/omarchy/shell.json.
SHELL_CONFIG = r"""CONFIG_FILE="$HOME/.config/omarchy/shell.json"
NORMALIZE='if type == "object" then . else {} end'
commit() {
  local program="$1"; shift
  mkdir -p "$(dirname "$CONFIG_FILE")"
  [ -s "$CONFIG_FILE" ] || echo '{}' > "$CONFIG_FILE"
  jq -S -e "$@" "$program" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || { echo "could not update shell config" >&2; exit 1; }
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  echo "commit" >> "$CALLS"
}
"""
TOGGLE = """echo "toggle $*" >> "$CALLS"
f="$HOME/.local/state/omarchy/toggles/$1"
case "$2" in on) mkdir -p "$(dirname "$f")"; touch "$f" ;; off) rm -f "$f" ;; esac
"""
LOGGER = """echo "$(basename "$0") $*" >> "$CALLS"
"""


class ScreensaverTest(LookTest):
    def setUp(self):
        super().setUp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        bin_dir = os.path.join(self.tmp, "bin")
        for name, script in (("omarchy-shell-config", SHELL_CONFIG), ("omarchy-toggle", TOGGLE),
                             ("omarchy-branding-screensaver", LOGGER), ("omarchy-launch-screensaver", LOGGER)):
            path = os.path.join(bin_dir, name)
            with open(path, "w") as f:
                f.write(("" if name == "omarchy-shell-config" else "#!/bin/sh\n") + script)
            os.chmod(path, 0o755)
        self.omarchy = os.path.join(self.tmp, "omarchy")
        os.makedirs(self.omarchy)
        with open(os.path.join(self.omarchy, "logo.txt"), "w") as f:
            f.write("OMARCHY\n")
        self.env = dict(self.env, HOME=self.home, OMARCHY_PATH=self.omarchy)
        self.shell_json = os.path.join(self.home, ".config", "omarchy", "shell.json")
        self.text = os.path.join(self.home, ".config", "omarchy", "branding", "screensaver.txt")

    def saver(self):
        r = self.look("screensaver")
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def calls_named(self, prefix):
        return [c for c in self.omarchy_calls() if c.startswith(prefix)]

    def wait_for_call(self, prefix):
        # Detached commands log a moment after fathom-look returns.
        for _ in range(50):
            if self.calls_named(prefix):
                return self.calls_named(prefix)
            time.sleep(0.05)
        return []

    def test_with_nothing_set_it_reads_omarchys_defaults(self):
        self.assertEqual(self.saver(), {"on": True, "after": 150, "lockAfter": 300, "shows": "omarchy",
                                        "blueprint": False, "service": None,
                                    "limits": {"after": [30, 7200], "lockAfter": [60, 7200]}})
        self.assertIn("screensaver", json.loads(self.look("state").stdout))

    def test_times_go_into_shell_json_and_keep_the_rest(self):
        os.makedirs(os.path.dirname(self.shell_json))
        with open(self.shell_json, "w") as f:
            json.dump({"bar": {"background": "glassy"}, "idle": {"lock": 300}}, f)
        self.assertEqual(self.look("screensaver", "after", "600").returncode, 0)
        self.assertEqual(self.look("screensaver", "lock-after", "0").returncode, 0)
        config = json.loads(read(self.shell_json))
        self.assertEqual(config["idle"], {"screensaver": 600, "lock": 0})
        self.assertEqual(config["bar"], {"background": "glassy"})
        s = self.saver()
        self.assertEqual((s["after"], s["lockAfter"]), (600, 0))

    def test_bad_times_change_nothing(self):
        for args in (("after", "10"), ("after", "9000"), ("after", "0"), ("after", "soon"),
                     ("lock-after", "30"), ("lock-after", "-1"), ("what",), ("shows", "nothing")):
            r = self.look("screensaver", *args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("fathom-look:", r.stderr)
        self.assertFalse(os.path.exists(self.shell_json))
        self.assertEqual(self.calls_named("commit"), [])

    def test_off_and_on_use_omarchys_toggle(self):
        self.assertEqual(self.look("screensaver", "off").returncode, 0)
        self.assertFalse(self.saver()["on"])
        self.assertEqual(self.look("screensaver", "on").returncode, 0)
        self.assertTrue(self.saver()["on"])
        self.assertEqual(self.calls_named("toggle"), ["toggle screensaver-off on", "toggle screensaver-off off"])
        # Picking a time while it's off turns it on.
        self.assertEqual(self.look("screensaver", "off").returncode, 0)
        self.assertEqual(self.look("screensaver", "after", "300").returncode, 0)
        s = self.saver()
        self.assertEqual((s["on"], s["after"]), (True, 300))

    def test_on_after_a_zero_time_brings_back_omarchys_time(self):
        os.makedirs(os.path.dirname(self.shell_json))
        with open(self.shell_json, "w") as f:
            json.dump({"idle": {"screensaver": 0}}, f)
        self.assertFalse(self.saver()["on"])
        self.assertEqual(self.look("screensaver", "on").returncode, 0)
        self.assertEqual(json.loads(read(self.shell_json))["idle"]["screensaver"], 150)

    def test_what_it_shows(self):
        self.assertEqual(self.look("screensaver", "shows", "fathom").returncode, 0)
        self.assertIn("▄████████", read(self.text))
        self.assertEqual(self.saver()["shows"], "fathom")
        self.assertEqual(self.look("screensaver", "shows", "omarchy").returncode, 0)
        self.assertEqual(read(self.text), "OMARCHY\n")
        self.assertEqual(self.saver()["shows"], "omarchy")
        with open(self.text, "w") as f:
            f.write("mine\n")
        self.assertEqual(self.saver()["shows"], "custom")
        self.assertEqual(self.look("screensaver", "shows", "picture").returncode, 0)
        self.assertEqual(self.wait_for_call("omarchy-branding-screensaver"), ["omarchy-branding-screensaver image"])

    def test_preview_runs_omarchys_launcher(self):
        self.assertEqual(self.look("screensaver", "preview").returncode, 0)
        self.assertEqual(self.wait_for_call("omarchy-launch-screensaver"), ["omarchy-launch-screensaver force"])

    def fathom_idle(self):
        """Fathom's idle service (install.sh --screensaver) in use, with a
        stand-in fathom-screensaver that keeps what it shows in a file."""
        plugin = os.path.join(self.home, ".config", "omarchy", "plugins", "fathom.idle")
        os.makedirs(plugin)
        with open(os.path.join(plugin, "manifest.json"), "w") as f:
            json.dump({"id": "fathom.idle", "name": "Fathom Idle", "omarchy": {"clonedFrom": "omarchy.idle"},
                       "entryPoints": {"service": "Service.qml"}}, f)
        with open(os.path.join(plugin, "Service.qml"), "w") as f:
            f.write('runProcess(screensaverProcess, "screensaver", '
                    '"[[ $(omarchy-shell lock isLocked 2>/dev/null) == \\"true\\" ]] || $HOME/.local/bin/fathom-screensaver")\n')
        launcher = os.path.join(self.home, ".local", "bin", "fathom-screensaver")
        os.makedirs(os.path.dirname(launcher))
        self.shows_file = os.path.join(self.tmp, "fathom-shows")
        with open(launcher, "w") as f:
            f.write("#!/bin/sh\n" + LOGGER.replace("$0", "fathom-screensaver") +
                    f'if [ "$1" = shows ]; then\n  if [ -n "$2" ]; then echo "$2" > {self.shows_file}; '
                    f'else cat {self.shows_file} 2>/dev/null || echo blueprint; fi\nfi\n')
        os.chmod(launcher, 0o755)
        os.makedirs(os.path.dirname(self.shell_json), exist_ok=True)
        with open(self.shell_json, "w") as f:
            json.dump({"plugins": [{"id": "fathom.idle"}]}, f)

    def test_fathoms_screensaver_offers_blueprint(self):
        self.fathom_idle()
        s = self.saver()
        self.assertEqual((s["blueprint"], s["shows"], s["service"]), (True, "blueprint", None))
        # Picking what Omarchy's shows goes back to Omarchy's screensaver.
        self.assertEqual(self.look("screensaver", "shows", "fathom").returncode, 0)
        self.assertEqual(self.calls_named("fathom-screensaver shows "), ["fathom-screensaver shows omarchy"])
        s = self.saver()
        self.assertEqual((s["blueprint"], s["shows"]), (True, "fathom"))
        self.assertEqual(self.look("screensaver", "shows", "blueprint").returncode, 0)
        self.assertEqual(self.saver()["shows"], "blueprint")
        self.assertEqual(self.look("screensaver", "preview").returncode, 0)
        self.assertEqual(self.wait_for_call("fathom-screensaver force"), ["fathom-screensaver force"])

    def test_no_blueprint_without_fathoms_screensaver(self):
        self.assertFalse(self.saver()["blueprint"])
        r = self.look("screensaver", "shows", "blueprint")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--screensaver", r.stderr)

    def test_a_cloned_idle_service_is_named_and_its_launcher_previewed(self):
        plugin = os.path.join(self.home, ".config", "omarchy", "plugins", "me.idle")
        os.makedirs(plugin)
        with open(os.path.join(plugin, "manifest.json"), "w") as f:
            json.dump({"id": "me.idle", "name": "My Idle", "omarchy": {"clonedFrom": "omarchy.idle"},
                       "entryPoints": {"service": "Service.qml"}}, f)
        launcher = os.path.join(self.tmp, "bin", "my-saver")
        with open(launcher, "w") as f:
            f.write("#!/bin/sh\n" + LOGGER)
        os.chmod(launcher, 0o755)
        with open(os.path.join(plugin, "Service.qml"), "w") as f:
            f.write('runProcess(screensaverProcess, "screensaver", '
                    '"[[ $(omarchy-shell lock isLocked 2>/dev/null) == \\"true\\" ]] || ' + launcher + '")\n')
        os.makedirs(os.path.dirname(self.shell_json), exist_ok=True)
        with open(self.shell_json, "w") as f:
            json.dump({"plugins": [{"id": "me.idle"}]}, f)
        self.assertEqual(self.saver()["service"], "My Idle")
        self.assertEqual(self.look("screensaver", "preview").returncode, 0)
        self.assertEqual(self.wait_for_call("my-saver"), ["my-saver force"])
        self.assertEqual(self.calls_named("omarchy-launch-screensaver"), [])

    # The look's own tests aren't run again here.
    test_fathoms_own_look_rebuilds_the_theme_unchanged = None
    test_a_changed_look_rewrites_colours_corners_and_panels = None
    test_a_solid_frame_is_one_colour = None
    test_the_built_hyprland_file_is_valid_lua = None
    test_bad_values_change_nothing = None
    test_an_unreadable_look_file_is_fathoms_own = None
    test_a_theme_folder_the_user_made_is_left_alone = None
    test_an_older_install_link_is_replaced_by_a_built_folder = None
    test_it_refreshes_the_theme_only_when_fathom_is_on = None
    test_a_failed_refresh_is_reported = None
    test_state_lists_the_bar_blur_and_wallpapers = None
    test_bar_and_wallpaper_go_to_omarchy = None


if __name__ == "__main__":
    unittest.main()

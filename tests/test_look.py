"""fathom-look, run against a scratch home with stand-ins for omarchy and
hyprctl: Fathom's own look rebuilds theme/ unchanged, a changed look
rewrites only what it should, bad values change nothing, a theme folder the
user made is left alone, and the theme refreshes only when Fathom is on."""

import json
import os
import shutil
import subprocess
import tempfile
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


if __name__ == "__main__":
    unittest.main()

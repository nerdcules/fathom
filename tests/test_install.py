"""install.sh when a step fails, in a sandbox (tests/install_env.py): a
scratch HOME, and stand-ins for omarchy, hyprctl, systemctl, sudo, pkexec
and the rest that record their arguments and change nothing. A stand-in
can be told to fail, to see that the plugin, theme and selection you had
stay, that a stopped install says what finished and how to carry on, and
that running it again ends where an install that never failed does."""

import os
import re
import shlex
import unittest

from install_env import REPO, Sandbox

DEFAULT = ["--skin", "--player", "--deck", "--desk", "--mail"]


def read(path):
    with open(path, "rb") as f:
        return f.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def normalised(box):
    """A sandbox's HOME as a whole, without its own path or backup times."""
    out = {}
    for k, v in box.snapshot().items():
        k = re.sub(r"\.bak\.\d+$", ".bak.N", k)
        if isinstance(v, bytes):
            v = v.replace(box.tmp.encode(), b"<sandbox>")
        else:
            v = v.replace(box.tmp, "<sandbox>")
        out[k] = v
    return out


class Install(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()
        self.addCleanup(self.box.cleanup)

    def install(self, *args, **kw):
        return self.box.run("install.sh", *args, **kw)

    def ok(self, *args, **kw):
        r = self.install(*args, **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def tree(self, *parts):
        """A folder's files, by path inside it."""
        top = self.box.path(*parts)
        return {k[len(os.path.join(*parts)) + 1:]: v for k, v in self.box.snapshot().items()
                if k.startswith(os.path.join(*parts) + os.sep)} if os.path.isdir(top) else None

    def selected(self):
        p = os.path.join(self.box.stub_state, "theme")
        return read(p).decode().strip() if os.path.exists(p) else "Tokyo Night"

    def installed_parts(self):
        return read(self.box.path(".local/state/fathom/installed")).decode().split()

    # ------------------------------------------------------------ plugins

    def test_a_plugin_that_fails_validation_leaves_the_one_you_had(self):
        self.ok()
        write(self.box.path(".config/omarchy/plugins/fathom.deck/OLD"), "the version you had\n")
        write(self.box.path(".local/bin/fathom-deck"), "the deck command you had\n")
        before = self.tree(".config", "omarchy", "plugins", "fathom.deck")
        self.box.clear_calls()
        r = self.install(fail=["omarchy plugin validate */fathom.deck"])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.tree(".config", "omarchy", "plugins", "fathom.deck"), before)
        # Checked before anything of the deck changed.
        self.assertEqual(read(self.box.path(".local/bin/fathom-deck")), b"the deck command you had\n")
        self.assertFalse([c for c in self.box.calls() if "fathom.deck" in c and "validate" not in c])
        self.assertIn("the one you had is unchanged", r.stderr)
        self.assertFalse(os.path.exists(self.box.path(".local/state/fathom/staging")))

    def test_a_plugin_omarchy_wont_turn_on_is_swapped_back(self):
        self.ok()
        write(self.box.path(".config/omarchy/plugins/fathom.desk/OLD"), "the version you had\n")
        before = self.tree(".config", "omarchy", "plugins", "fathom.desk")
        r = self.install("--desk", fail=["omarchy plugin enable fathom.desk*"])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.tree(".config", "omarchy", "plugins", "fathom.desk"), before)
        self.assertEqual(len([c for c in self.box.calls() if c.startswith("omarchy plugin enable fathom.desk")]),
                         1 + 10, "one enable on the first install, then ten tries")
        self.assertIn("the one you had is back", r.stderr)

    # ------------------------------------------------------------ theme

    def mark_old_theme(self):
        """An installed Fathom theme, marked so a replacement would show."""
        self.ok("--skin")
        write(self.box.path(".local/share/fathom/theme/OLD"), "shipped theme you had\n")
        write(self.box.path(".config/omarchy/themes/fathom/OLD"), "built theme you had\n")
        write(self.box.path(".local/bin/fathom-look"), "#!/bin/sh\n# the fathom-look you had\n")
        return (self.tree(".local", "share", "fathom", "theme"), self.tree(".config", "omarchy", "themes", "fathom"),
                read(self.box.path(".local/bin/fathom-look")))

    def test_a_theme_that_fails_to_build_leaves_the_theme_you_had(self):
        before = self.mark_old_theme()
        self.box.clear_calls()
        r = self.install("--skin", STUB_FAIL_LOOK_BUILD="1")
        self.assertEqual(r.returncode, 1)
        after = (self.tree(".local", "share", "fathom", "theme"), self.tree(".config", "omarchy", "themes", "fathom"),
                 read(self.box.path(".local/bin/fathom-look")))
        self.assertEqual(after, before)
        self.assertEqual(self.selected(), "fathom")
        self.assertFalse([c for c in self.box.calls() if c.startswith("omarchy theme set")])
        self.assertIn("didn't build", r.stderr)

    def test_a_theme_omarchy_wont_switch_to_leaves_the_theme_you_had(self):
        before = self.mark_old_theme()
        r = self.install("--skin", fail=["omarchy theme set fathom"])
        self.assertEqual(r.returncode, 1)
        after = (self.tree(".local", "share", "fathom", "theme"), self.tree(".config", "omarchy", "themes", "fathom"),
                 read(self.box.path(".local/bin/fathom-look")))
        self.assertEqual(after, before)
        self.assertEqual(self.selected(), "fathom")
        self.assertIn("omarchy theme set \"fathom\"", r.stderr)

    def test_a_first_install_omarchy_wont_switch_to_puts_your_theme_back(self):
        # Your own theme called fathom, and Tokyo Night on.
        write(self.box.path(".config/omarchy/themes/fathom/colors.toml"), "# yours\n")
        r = self.install("--skin", fail=["omarchy theme set fathom"])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.tree(".config", "omarchy", "themes", "fathom"), {"colors.toml": b"# yours\n"})
        self.assertFalse([p for p in os.listdir(self.box.path(".config/omarchy/themes")) if ".bak." in p])
        self.assertFalse(os.path.exists(self.box.path(".local/share/fathom/theme")))
        self.assertFalse(os.path.exists(self.box.path(".local/bin/fathom-look")))
        self.assertEqual(self.selected(), "Tokyo Night")
        self.assertIn("omarchy theme set Tokyo Night", self.box.calls())

    # ------------------------------------------------------------ the run as a whole

    def test_a_later_part_failing_says_what_finished_and_the_command_to_carry_on(self):
        r = self.install(fail=["omarchy plugin validate */fathom.desk"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("--desk failed", r.stderr)
        self.assertIn("Installed in this run: --skin --player --deck", r.stderr)
        self.assertIn("Not done in this run: --desk --mail", r.stderr)
        self.assertEqual(self.installed_parts(), ["skin", "player", "deck"])
        lines = r.stderr.splitlines()
        carry_on = shlex.split(lines[lines.index(next(l for l in lines if l.startswith("To carry on"))) + 1])
        self.assertEqual(carry_on, [os.path.join(REPO, "install.sh"), "--desk", "--mail"])
        self.assertIn(os.path.join(REPO, "uninstall.sh"), r.stderr)

        # The command it gave finishes the job: the same as one clean install.
        self.ok(*carry_on[1:])
        self.assertEqual(self.installed_parts(), ["skin", "player", "deck", "desk", "mail"])
        clean = Sandbox()
        self.addCleanup(clean.cleanup)
        r = clean.run("install.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(normalised(self.box), normalised(clean))

    def test_the_command_to_carry_on_keeps_the_options(self):
        r = self.install("--link", "--no-apply", "--skin", "--desk", fail=["omarchy plugin validate */fathom.desk"])
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"{REPO}/install.sh --desk --link --no-apply", r.stderr)

    def test_running_it_again_changes_nothing_and_keeps_your_files(self):
        yours = {
            ".config/omarchy/themes/other/colors.toml": "# another theme\n",
            ".config/omarchy/plugins/someone.clock/manifest.json": "{}\n",
            ".config/fathom/look.json": '{"accent": "#ff6b81"}\n',
            ".config/systemd/user/mine.service": "[Unit]\n",
            ".local/bin/mytool": "#!/bin/sh\n",
            ".local/share/fathom/notes.txt": "mine\n",
        }
        for rel, text in yours.items():
            write(self.box.path(rel), text)
        self.ok()
        once = self.box.snapshot()
        self.ok()
        self.assertEqual(self.box.snapshot(), once)
        for rel, text in yours.items():
            self.assertEqual(read(self.box.path(rel)).decode(), text, rel)
        lua = read(self.box.path(".config/hypr/hyprland.lua")).decode()
        self.assertTrue(lua.startswith("-- the user's own Hyprland file\nrequire(\"omarchy\")\n"))
        self.assertEqual(lua.count('require("hypr.fathom-deck")'), 1)

    def test_an_install_that_was_killed_is_put_back_on_the_next_run(self):
        # Killed after the deck plugin you had was moved aside, before the
        # new one went in.
        self.ok()
        plugins = self.box.path(".config/omarchy/plugins")
        stage = self.box.path(".local/state/fathom/staging")
        os.makedirs(stage)
        os.rename(os.path.join(plugins, "fathom.deck"), os.path.join(stage, "fathom.deck.prev"))
        write(os.path.join(stage, "fathom.deck.prev", "OLD"), "the version you had\n")
        self.ok("--mail")
        self.assertEqual(read(os.path.join(plugins, "fathom.deck", "OLD")), b"the version you had\n")
        self.assertFalse(os.path.exists(stage))


if __name__ == "__main__":
    unittest.main()

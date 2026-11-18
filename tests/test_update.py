"""fathom-update against real git repositories in a scratch home: a bare
"remote", the clone Fathom was installed from, and new commits and tags
pushed upstream. install.sh in the clone is a stand-in that records what it
was asked to install, as the real one records its source."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPDATE = os.path.join(REPO_ROOT, "update", "bin", "fathom-update")

STAND_IN_INSTALL = """#!/bin/bash
# Records its arguments and, like install.sh, where it installed from.
echo "$*" >> "$CALLS"
state="$XDG_STATE_HOME/fathom"; mkdir -p "$state"
link=false; for a in "$@"; do [ "$a" = --link ] && link=true; done
cat > "$state/source" <<EOF
{"repo": "$(cd "$(dirname "$0")" && pwd)", "commit": "$(git -C "$(dirname "$0")" rev-parse HEAD)",
 "branch": "main", "link": $link, "apply": true, "opensnitch": false, "parts": ["desk", "sentinel"]}
EOF
"""


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.calls = os.path.join(self.tmp, "calls")
        self.env = dict(os.environ, HOME=self.home, XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
                        XDG_STATE_HOME=os.path.join(self.home, ".local", "state"), CALLS=self.calls,
                        GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
                        GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid",
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                        FATHOM_UPDATE_SDDM_THEME=os.path.join(self.tmp, "no-sddm-theme"))
        self.origin = os.path.join(self.tmp, "origin.git")
        self.up = os.path.join(self.tmp, "upstream")      # where "the author" works
        self.repo = os.path.join(self.tmp, "fathom")       # the user's clone
        self.git(self.tmp, "init", "-q", "--bare", "-b", "main", self.origin)
        self.git(self.tmp, "clone", "-q", self.origin, self.up)
        self.write(self.up, "install.sh", STAND_IN_INSTALL, mode=0o755)
        self.write(self.up, "desk/plugin.qml", "v1\n")
        self.write(self.up, "sentinel/root/admin", "v1\n")
        self.write(self.up, "README.md", "v1\n")
        self.commit(self.up, "first", tag="v0.1.0")
        self.git(self.tmp, "clone", "-q", self.origin, self.repo)
        self.install()                                      # installed at v0.1.0

    def tearDown(self):
        shutil.rmtree(self.tmp)

    # helpers
    def git(self, cwd, *args):
        return subprocess.run(["git", *args], cwd=cwd, env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, repo, path, text, mode=None):
        full = os.path.join(repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)
        if mode:
            os.chmod(full, mode)

    def commit(self, repo, msg, tag=None):
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-q", "-m", msg)
        if tag:
            self.git(repo, "tag", tag)
        self.git(repo, "push", "-q", "--tags", "origin", "main")
        return self.git(repo, "rev-parse", "HEAD")

    def install(self):
        subprocess.run([os.path.join(self.repo, "install.sh"), "--desk", "--sentinel", "--link"],
                       env=self.env, check=True)
        os.remove(self.calls)

    def update(self, *args):
        return subprocess.run([UPDATE, *args], env=self.env, capture_output=True, text=True, timeout=60)

    def checked(self, *extra):
        r = self.update("check", "--json", *extra)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def install_calls(self):
        return open(self.calls).read().splitlines() if os.path.exists(self.calls) else []

    def head(self):
        return self.git(self.repo, "rev-parse", "HEAD")

    # tests
    def test_up_to_date(self):
        r = self.checked()
        self.assertFalse(r["available"])
        self.assertEqual(r["version"], "v0.1.0")
        self.assertIn("up to date", self.update("check").stdout)

    def test_releases_follow_the_newest_semantic_version_never_a_prerelease(self):
        self.write(self.up, "desk/plugin.qml", "v2\n")
        self.commit(self.up, "desk change", tag="v0.2.0")
        self.write(self.up, "README.md", "v3\n")
        self.commit(self.up, "readme change", tag="v0.10.0")
        self.write(self.up, "desk/plugin.qml", "v4\n")
        self.commit(self.up, "try this", tag="v0.11.0-rc1")
        r = self.checked()
        self.assertEqual(r["target"], "v0.10.0")       # 10 > 2, and the rc is left out
        self.assertTrue(r["available"])
        self.assertEqual([c.split(" ", 1)[1] for c in r["commits"]], ["readme change", "desk change"])
        self.assertEqual(r["parts"], ["desk"])
        self.assertFalse(r["needsPassword"])

    def test_apply_fast_forwards_and_reinstalls_only_what_changed(self):
        self.write(self.up, "desk/plugin.qml", "v2\n")
        new = self.commit(self.up, "desk change", tag="v0.2.0")
        old = self.head()
        r = self.update("apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head(), new)
        self.assertEqual(self.install_calls(), ["--desk --link"])
        self.assertIn("Updated Fathom to v0.2.0", r.stdout)
        with open(os.path.join(self.home, ".local/state/fathom/update-previous")) as f:
            self.assertEqual(f.read().strip(), old)
        self.assertFalse(self.checked()["available"])

    def test_rollback_goes_back_and_reinstalls(self):
        self.write(self.up, "desk/plugin.qml", "v2\n")
        self.commit(self.up, "desk change", tag="v0.2.0")
        old = self.head()
        self.assertEqual(self.update("apply").returncode, 0)
        os.remove(self.calls)
        r = self.update("rollback")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head(), old)
        self.assertEqual(self.install_calls(), ["--desk --link"])
        self.assertEqual(self.update("rollback").returncode, 1)   # nothing further back

    def test_a_root_part_change_says_it_needs_the_password(self):
        self.write(self.up, "sentinel/root/admin", "v2\n")
        self.commit(self.up, "helper change", tag="v0.2.0")
        r = self.checked()
        self.assertEqual(r["parts"], ["sentinel"])
        self.assertTrue(r["needsPassword"])
        self.assertIn("asks for your password", self.update("check").stdout)

    def test_an_installer_change_reinstalls_every_installed_part(self):
        with open(os.path.join(self.up, "install.sh"), "a") as f:
            f.write("# changed\n")
        self.commit(self.up, "installer change", tag="v0.2.0")
        self.assertEqual(self.checked()["parts"], ["desk", "sentinel"])

    def test_no_release_yet_on_the_releases_channel(self):
        for repo in (self.up, self.repo):
            self.git(repo, "tag", "-d", "v0.1.0")
        self.git(self.up, "push", "-q", "origin", ":refs/tags/v0.1.0")
        self.write(self.up, "desk/plugin.qml", "v2\n")
        self.commit(self.up, "untagged")
        r = self.checked()
        self.assertFalse(r["available"])
        self.assertIn("no release has been published yet", r["note"])
        self.update("channel", "main")
        r = self.checked()
        self.assertTrue(r["available"])
        self.assertEqual(r["target"], "origin/main")

    def test_your_own_changes_block_the_update(self):
        self.write(self.up, "desk/plugin.qml", "v2\n")
        self.commit(self.up, "desk change", tag="v0.2.0")
        self.write(self.repo, "README.md", "mine\n")
        before = self.head()
        self.assertIn("aren't committed", self.checked()["blocked"])
        r = self.update("apply")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.head(), before)
        self.assertEqual(self.install_calls(), [])

    def test_your_own_commits_block_the_update(self):
        self.write(self.up, "desk/plugin.qml", "v2\n")
        self.commit(self.up, "desk change", tag="v0.2.0")
        self.write(self.repo, "notes.txt", "mine\n")
        self.git(self.repo, "add", "notes.txt")
        self.git(self.repo, "commit", "-q", "-m", "mine")
        self.assertIn("has commits that", self.checked()["blocked"])
        self.assertEqual(self.update("apply").returncode, 1)

    def test_status_never_goes_online_and_auto_is_off_by_default(self):
        self.checked()
        self.git(self.repo, "remote", "set-url", "origin", os.path.join(self.tmp, "gone.git"))
        r = self.update("status")
        self.assertEqual(r.returncode, 0)
        self.assertIn('"available": false', r.stdout)
        self.assertEqual(self.update("check").returncode, 1)            # fetch fails
        os.remove(os.path.join(self.home, ".local/state/fathom/update.json"))
        self.assertEqual(self.update("check", "--auto").returncode, 0)  # off: does nothing
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local/state/fathom/update.json")))
        self.update("auto", "on")
        self.assertEqual(self.update("check", "--auto").returncode, 1)  # on: it tries

    def test_an_install_from_before_parts_were_recorded(self):
        source = os.path.join(self.home, ".local/state/fathom/source")
        with open(source) as f:
            data = json.load(f)
        data.pop("parts")
        with open(source, "w") as f:
            json.dump(data, f)
        os.makedirs(os.path.join(self.home, ".local/bin"))
        open(os.path.join(self.home, ".local/bin/fathom-desk"), "w").close()
        self.assertEqual(self.checked()["installedParts"], ["desk"])

    def test_version_says_what_install_sh_recorded(self):
        source = os.path.join(self.home, ".local/state/fathom/source")
        with open(source) as f:
            data = json.load(f)
        r = self.update("version")
        self.assertIn("version not recorded (installed at", r.stdout)  # the stand-in installer doesn't record one
        data.update(version="0.1.0", build=4, versionText="v0.1.0 · build 4 · abc1234")
        with open(source, "w") as f:
            json.dump(data, f)
        self.assertEqual(self.update("version").stdout.strip(), "Fathom v0.1.0 · build 4 · abc1234")
        j = json.loads(self.update("version", "--json").stdout)
        self.assertEqual((j["version"], j["build"], j["text"]), ("0.1.0", 4, "v0.1.0 · build 4 · abc1234"))
        os.remove(source)
        self.assertEqual(self.update("version").stdout.strip(), "Fathom not installed")

    def test_without_a_record_it_says_how_to_make_one(self):
        os.remove(os.path.join(self.home, ".local/state/fathom/source"))
        r = self.update("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Run ./install.sh once more", r.stderr)


if __name__ == "__main__":
    unittest.main()

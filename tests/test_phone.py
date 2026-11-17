"""fathom-phone's service, run for real on a local port in a scratch home,
talked to as the phone will: TLS pinned to the certificate's fingerprint
from the pairing data. Pairing (single use, expiry, wrong tries), tokens,
unpairing, and what a paired phone can read."""

import hashlib
import http.client
import json
import os
import shutil
import socket
import ssl
import stat
import subprocess
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHONE = os.path.join(REPO, "phone", "bin", "fathom-phone")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class PhoneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        bin_dir = os.path.join(self.home, ".local", "bin")
        os.makedirs(bin_dir)
        # A part that answers, one that fails; the others aren't installed.
        for name, script in (("fathom-deck", 'echo \'{"system": {"cpu": 12}}\''), ("fathom-care", "exit 1")):
            path = os.path.join(bin_dir, name)
            with open(path, "w") as f:
                f.write("#!/bin/sh\n" + script + "\n")
            os.chmod(path, 0o755)
        self.port = free_port()
        self.env = dict(os.environ, HOME=self.home, XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
                        XDG_STATE_HOME=os.path.join(self.home, ".local", "state"),
                        FATHOM_PHONE_PORT=str(self.port), FATHOM_PHONE_BIND="127.0.0.1")
        self.server = subprocess.Popen([PHONE, "serve"], env=self.env, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", self.port), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.05)
        else:
            self.fail("the service didn't start: " + self.server.stderr.read().decode()[:300])

    def tearDown(self):
        self.server.terminate()
        self.server.wait(timeout=10)
        self.server.stderr.close()
        shutil.rmtree(self.tmp)

    def run_phone(self, *args):
        return subprocess.run([PHONE, *args], env=self.env, capture_output=True, text=True, timeout=30)

    def window(self):
        r = self.run_phone("pair", "--json", "--no-wait")
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def call(self, method, path, fp, body=None, token=None, raw=None):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE   # pinned below instead, as the phone does
        conn = http.client.HTTPSConnection("127.0.0.1", self.port, context=ctx, timeout=10)
        conn.connect()
        der = conn.sock.getpeercert(binary_form=True)
        self.assertEqual(hashlib.sha256(der).hexdigest(), fp, "certificate isn't the pinned one")
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        if data is not None:
            headers["Content-Type"] = "application/json"
        conn.request(method, path, body=data, headers=headers)
        r = conn.getresponse()
        out = r.read()
        conn.close()
        return r.status, (json.loads(out) if out else None)

    def paired(self):
        w = self.window()
        code, body = self.call("POST", "/v1/pair", w["fingerprint"], {"secret": w["secret"], "name": "Pixel"})
        self.assertEqual(code, 200, body)
        return w["fingerprint"], body

    # tests
    def test_hello_is_open_and_says_nothing_private(self):
        fp = self.window()["fingerprint"]
        code, body = self.call("GET", "/v1/hello", fp)
        self.assertEqual((code, body), (200, {"app": "fathom-phone", "api": 1}))

    def test_nothing_else_without_a_token(self):
        fp = self.window()["fingerprint"]
        for path in ("/v1/status", "/v1/part/deck"):
            self.assertEqual(self.call("GET", path, fp)[0], 401)
            self.assertEqual(self.call("GET", path, fp, token="made-up")[0], 401)

    def test_pairing_gives_a_token_once(self):
        w = self.window()
        self.assertIn(f"secret={w['secret']}", w["uri"])
        self.assertIn(f"fp={w['fingerprint']}", w["uri"])
        code, body = self.call("POST", "/v1/pair", w["fingerprint"], {"secret": w["secret"], "name": "Pixel"})
        self.assertEqual(code, 200)
        self.assertEqual(self.call("GET", "/v1/part/deck", w["fingerprint"], token=body["token"])[0], 200)
        # The same secret again: the window closed when it was used.
        self.assertEqual(self.call("POST", "/v1/pair", w["fingerprint"], {"secret": w["secret"]})[0], 403)

    def test_no_window_no_pairing(self):
        fp = self.window()["fingerprint"]
        os.remove(os.path.join(self.home, ".local/state/fathom/phone/pairing.json"))
        self.assertEqual(self.call("POST", "/v1/pair", fp, {"secret": "anything"})[0], 403)

    def test_an_expired_window(self):
        w = self.window()
        path = os.path.join(self.home, ".local/state/fathom/phone/pairing.json")
        with open(path) as f:
            data = json.load(f)
        data["expires"] = int(time.time()) - 1
        with open(path, "w") as f:
            json.dump(data, f)
        self.assertEqual(self.call("POST", "/v1/pair", w["fingerprint"], {"secret": w["secret"]})[0], 403)

    def test_five_wrong_tries_close_the_window(self):
        w = self.window()
        for _ in range(5):
            self.assertEqual(self.call("POST", "/v1/pair", w["fingerprint"], {"secret": "wrong"})[0], 403)
        self.assertEqual(self.call("POST", "/v1/pair", w["fingerprint"], {"secret": w["secret"]})[0], 403)

    def test_a_paired_phone_reads_the_parts(self):
        fp, dev = self.paired()
        code, body = self.call("GET", "/v1/status", fp, token=dev["token"])
        self.assertEqual(code, 200)
        self.assertEqual(body["deck"], {"system": {"cpu": 12}})
        self.assertIsNone(body["care"])        # its command failed
        self.assertIsNone(body["sentinel"])    # not installed
        self.assertEqual(self.call("GET", "/v1/part/nope", fp, token=dev["token"])[0], 404)

    def test_tokens_are_kept_only_as_hashes_in_a_private_file(self):
        fp, dev = self.paired()
        path = os.path.join(self.home, ".config/fathom/phone.json")
        with open(path) as f:
            text = f.read()
        self.assertNotIn(dev["token"], text)
        self.assertIn(hashlib.sha256(dev["token"].encode()).hexdigest(), text)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        key = os.path.join(self.home, ".local/state/fathom/phone/key.pem")
        self.assertEqual(stat.S_IMODE(os.stat(key).st_mode), 0o600)

    def test_unpair_stops_the_token(self):
        fp, dev = self.paired()
        self.assertIn("Pixel", self.run_phone("devices").stdout)
        self.assertEqual(self.run_phone("unpair", dev["deviceId"]).returncode, 0)
        self.assertEqual(self.call("GET", "/v1/status", fp, token=dev["token"])[0], 401)
        self.assertEqual(self.run_phone("unpair", dev["deviceId"]).returncode, 1)

    def test_a_large_body_is_refused(self):
        w = self.window()
        code, _ = self.call("POST", "/v1/pair", w["fingerprint"], raw=b"x" * 5000)
        self.assertEqual(code, 413)

    def test_status_names_the_fingerprint_the_qr_code_carries(self):
        w = self.window()
        s = json.loads(self.run_phone("status").stdout)
        self.assertEqual(s["fingerprint"], w["fingerprint"])
        self.assertTrue(s["running"])


if __name__ == "__main__":
    unittest.main()

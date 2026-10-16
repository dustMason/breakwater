import functools
import hashlib
import http.server
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
spec = importlib.util.spec_from_file_location("fetch_assets", ROOT / "Scripts/fetch_assets.py")
fetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.source, self.remote = root / "source", root / "remote"
        self.source.mkdir()
        (self.remote / "objects").mkdir(parents=True)
        self.audio = b"audio fixture"
        self.key = "objects/" + hashlib.sha256(self.audio).hexdigest() + ".wav"
        (self.remote / self.key).write_bytes(self.audio)
        self.local_catalog = [{"id": "song", "loops": [{"id": 1, "file": "track/01.wav"}]}]
        self.remote_catalog = [{"id": "song", "loops": [{"id": 1, "file": self.key}]}]
        (self.source / "catalog.json").write_text(json.dumps(self.local_catalog))
        (self.remote / "catalog.json").write_text(json.dumps(self.remote_catalog))
        self.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(self.remote)))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}/"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def test_restore_and_preserve_local_files(self):
        self.assertEqual(fetch.restore(self.source, self.base), 1)
        path = self.source / "track/01.wav"
        self.assertEqual(path.read_bytes(), self.audio)
        self.assertEqual(fetch.restore(self.source, self.base), 0)
        path.write_bytes(b"personal work")
        with self.assertRaises(FileExistsError):
            fetch.restore(self.source, self.base)
        self.assertEqual(path.read_bytes(), b"personal work")

    def test_refuses_different_catalog_or_corrupt_object(self):
        self.remote_catalog[0]["id"] = "another song"
        (self.remote / "catalog.json").write_text(json.dumps(self.remote_catalog))
        with self.assertRaises(ValueError):
            fetch.restore(self.source, self.base)
        self.remote_catalog[0]["id"] = "song"
        (self.remote / "catalog.json").write_text(json.dumps(self.remote_catalog))
        (self.remote / self.key).write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            fetch.restore(self.source, self.base)
        self.assertFalse((self.source / "track/01.wav").exists())

    def test_restore_new_manifest_without_existing_local_catalog(self):
        fixture = json.loads((ROOT / "Tests/Fixtures/catalog.json").read_text())[:1]
        fixture[0]["loops"] = fixture[0]["loops"][:1]
        loop = fixture[0]["loops"][0]
        part_key = "objects/" + hashlib.sha256(self.audio).hexdigest() + ".m4a"
        (self.remote / part_key).write_bytes(self.audio)
        part_paths = loop["parts"]["files"]
        loop["parts"]["sourceFiles"], loop["parts"]["files"] = part_paths, [part_key] * 4
        relative = loop["file"]
        loop["sourceFile"], loop["file"] = relative, self.key
        (self.source / "catalog.json").unlink()
        (self.remote / "catalog.json").write_text(json.dumps(fixture))
        self.assertEqual(fetch.restore(self.source, self.base), 5)
        self.assertEqual((self.source / relative).read_bytes(), self.audio)
        self.assertTrue(all((self.source / path).read_bytes() == self.audio for path in part_paths))
        self.assertEqual(json.loads((self.source / "catalog.json").read_text())[0]["loops"][0]["file"], relative)

    def test_rejects_untrusted_paths(self):
        self.local_catalog[0]["loops"][0]["file"] = "../escape.wav"
        (self.source / "catalog.json").write_text(json.dumps(self.local_catalog))
        with self.assertRaises(ValueError):
            fetch.restore(self.source, self.base)
        with self.assertRaises(ValueError):
            fetch.base_url("http://example.com/")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Exercise catalog migration, recovery, and concurrent publication without AWS."""
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
import library
from library_catalog import source_catalog
from publish_assets import prepare_library


class FakeS3:
    def __init__(self, manifest, objects):
        self.items = {key: path.read_bytes() for key, path in objects.items()}
        self.items["catalog.json"] = json.dumps(manifest).encode()
        self.writes = []
        self.heads = []
        self.race = None

    def etag(self):
        return '"' + hashlib.md5(self.items["catalog.json"]).hexdigest() + '"'

    def get_object(self, **kwargs):
        return {"Body": io.BytesIO(self.items[kwargs["Key"]]), "ETag": self.etag()}

    def head_object(self, **kwargs):
        key = kwargs["Key"]
        self.heads.append(key)
        if key not in self.items:
            error = RuntimeError("missing")
            error.response = {"Error": {"Code": "404"}}
            raise error
        return {"ContentLength": len(self.items[key]), "Metadata": {"sha256": Path(key).stem}}

    def put_object(self, **kwargs):
        key = kwargs["Key"]
        if key == "catalog.json":
            if self.race is not None:
                self.items[key] = self.race
                self.race = None
            if "IfMatch" in kwargs and kwargs["IfMatch"] != self.etag():
                raise RuntimeError("catalog changed concurrently")
        body = kwargs["Body"]
        self.items[key] = body.read() if hasattr(body, "read") else body
        self.writes.append(key)

    def manifest(self):
        return json.loads(self.items["catalog.json"])


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.source = Path(self.temp.name) / "Samples"
        self.source.mkdir()
        self.catalog = json.loads((ROOT / "Tests/Fixtures/catalog.json").read_text())[:1]
        for song in self.catalog:
            for loop in song["loops"]:
                for name in [loop["file"], *loop["parts"]["files"]]:
                    path = self.source / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(name.encode())
        self.write(self.catalog)
        body, objects = prepare_library(self.source)
        self.modern = json.loads(body)
        self.remote = FakeS3(library.without_source_paths(self.modern), objects)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, catalog):
        (self.source / "catalog.json").write_bytes(library.json_bytes(catalog))

    def publish(self):
        return library.publish(self.source, self.remote, "example", "123456789012")

    def migrate(self):
        changed, _ = self.publish()
        self.assertTrue(changed)
        self.assertEqual(self.remote.writes, ["catalog.json"])
        self.assertEqual(self.remote.heads, [])
        self.assertEqual(source_catalog(self.remote.manifest())[0], self.catalog)

    def test_bootstrap_reuses_existing_objects_and_skips_unchanged_publish(self):
        self.migrate()
        self.remote.writes.clear()
        self.assertFalse(self.publish()[0])
        self.assertEqual(self.remote.writes, [])

    def test_fresh_pull_and_metadata_update_without_local_audio(self):
        self.migrate()
        for path in self.source.rglob("*"):
            if path.suffix in {".wav", ".m4a"}:
                path.unlink()
        catalog = self.source / "catalog.json"
        catalog.unlink()
        (self.source / ".catalog-base.json").unlink()
        self.assertEqual(library.pull(self.source, self.remote.manifest()), (1, 2))
        updated = json.loads(catalog.read_text())
        updated[0]["name"] = "Renamed"
        self.write(updated)
        self.remote.writes.clear()
        self.assertTrue(self.publish()[0])
        self.assertEqual(self.remote.writes, ["catalog.json"])
        self.assertEqual(source_catalog(self.remote.manifest())[0], updated)

    def test_pull_refuses_to_overwrite_edits(self):
        self.migrate()
        edited = copy.deepcopy(self.catalog)
        edited[0]["name"] = "Unpublished work"
        self.write(edited)
        upstream = copy.deepcopy(self.remote.manifest())
        upstream[0]["name"] = "Another edit"
        with self.assertRaisesRegex(ValueError, "unpublished edits"):
            library.pull(self.source, upstream)
        self.assertEqual(json.loads((self.source / "catalog.json").read_text()), edited)

    def test_publish_refuses_remote_changes_and_conditional_write_race(self):
        self.migrate()
        local = copy.deepcopy(self.catalog)
        local[0]["name"] = "Local edit"
        self.write(local)
        remote = self.remote.manifest()
        remote[0]["name"] = "Remote edit"
        self.remote.items["catalog.json"] = json.dumps(remote).encode()
        with self.assertRaisesRegex(ValueError, "changed since your last pull"):
            self.publish()
        self.assertEqual(self.remote.manifest(), remote)
        self.remote.items["catalog.json"] = json.dumps(self.modern).encode()
        competing = copy.deepcopy(self.modern)
        competing[0]["name"] = "Concurrent editor"
        self.remote.race = json.dumps(competing).encode()
        with self.assertRaisesRegex(RuntimeError, "concurrently"):
            self.publish()
        self.assertEqual(self.remote.manifest(), competing)

    def test_remote_audio_changes_do_not_silently_overwrite_local_audio(self):
        self.migrate()
        upstream = self.remote.manifest()
        new_audio = b"audio from another editor"
        new_key = "objects/" + hashlib.sha256(new_audio).hexdigest() + ".wav"
        upstream[0]["loops"][0]["file"] = new_key
        self.remote.items[new_key] = new_audio
        self.remote.items["catalog.json"] = json.dumps(upstream).encode()
        with self.assertRaisesRegex(ValueError, "changed since your last pull"):
            self.publish()
        with self.assertRaisesRegex(FileExistsError, "Local audio differs"):
            library.pull(self.source, upstream)
        self.assertEqual(self.remote.manifest(), upstream)

    def test_missing_new_file_and_invalid_metadata_cannot_publish(self):
        self.migrate()
        edited = copy.deepcopy(self.catalog)
        edited[0]["loops"][0]["file"] = "fixture/missing.wav"
        self.write(edited)
        self.remote.writes.clear()
        with self.assertRaises(FileNotFoundError):
            self.publish()
        self.assertEqual(self.remote.writes, [])
        edited[0]["loops"][0]["file"] = "../escape.wav"
        self.write(edited)
        with self.assertRaises(ValueError):
            self.publish()

    def test_changed_audio_uploads_before_manifest(self):
        self.migrate()
        path = self.source / self.catalog[0]["loops"][0]["file"]
        path.write_bytes(b"new version")
        self.remote.writes.clear()
        self.assertTrue(self.publish()[0])
        self.assertEqual(len(self.remote.writes), 2)
        self.assertTrue(self.remote.writes[0].startswith("objects/"))
        self.assertEqual(self.remote.writes[1], "catalog.json")

    def test_rejects_unsafe_or_conflicting_published_paths(self):
        bad = copy.deepcopy(self.modern)
        bad[0]["loops"][0]["sourceFile"] = "../outside.wav"
        with self.assertRaises(ValueError):
            library.pull(Path(self.temp.name) / "fresh", bad)
        bad = copy.deepcopy(self.modern)
        bad[0]["loops"][1]["sourceFile"] = bad[0]["loops"][0]["sourceFile"]
        with self.assertRaises(ValueError):
            source_catalog(bad)

    def test_optional_onepassword_credentials_never_need_a_credentials_file(self):
        item = {"fields": [{"label": "ACCESS_KEY_ID", "value": "fixture-key"},
                           {"label": "SECRET_ACCESS_KEY", "value": "fixture-secret"}]}
        session = Mock()
        with patch.dict("os.environ", {"BREAKWATER_1PASSWORD_ITEM": "item-id", "BREAKWATER_1PASSWORD_ACCOUNT": "account"}), \
             patch("library.subprocess.run") as command, patch.dict(sys.modules, {"boto3": SimpleNamespace(Session=session)}):
            command.return_value.stdout = json.dumps(item)
            library.aws_session()
        self.assertIn("item-id", command.call_args.args[0])
        self.assertIn("--account", command.call_args.args[0])
        self.assertEqual(session.call_args.kwargs["aws_access_key_id"], "fixture-key")
        self.assertEqual(session.call_args.kwargs["aws_secret_access_key"], "fixture-secret")


if __name__ == "__main__":
    unittest.main()

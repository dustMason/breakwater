#!/usr/bin/env python3
"""Exercise catalog publication without an AWS account."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publish_assets", root / "Scripts/publish_assets.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
sys.path.insert(0, str(root / "Scripts"))
import build_web


class Missing(Exception):
    response = {"Error": {"Code": "404"}}


class FakeS3:
    def __init__(self, fail=None):
        self.objects = {}
        self.calls = []
        self.fail = fail
        self.lock = threading.Lock()

    def head_object(self, *, Bucket, Key, ExpectedBucketOwner):
        with self.lock:
            if Key not in self.objects:
                raise Missing()
            value = self.objects[Key]
            return {"ContentLength": len(value["body"]), "Metadata": value["metadata"]}

    def put_object(self, *, Bucket, Key, Body, ExpectedBucketOwner, **kwargs):
        if Key == self.fail:
            raise RuntimeError("upload failed")
        body = Body.read() if hasattr(Body, "read") else Body
        with self.lock:
            self.calls.append(Key)
            self.objects[Key] = {"body": body, "metadata": kwargs.get("Metadata", {})}


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.source = Path(self.temp.name) / "source"
        self.source.mkdir()
        (self.source / "loop.wav").write_bytes(b"one")
        (self.source / "part.m4a").write_bytes(b"two")
        self.catalog = [{"id": "song", "loops": [{"id": 1, "file": "loop.wav",
                         "parts": {"files": ["part.m4a"]}}]}]
        self.write_catalog()

    def tearDown(self):
        self.temp.cleanup()

    def write_catalog(self):
        (self.source / "catalog.json").write_text(json.dumps(self.catalog))

    def test_content_addressing_and_idempotent_publication(self):
        body, objects = publisher.prepare_library(self.source)
        loop = json.loads(body)[0]["loops"][0]
        self.assertEqual(loop["file"], "objects/" + hashlib.sha256(b"one").hexdigest() + ".wav")
        self.assertEqual(len(objects), 2)
        s3 = FakeS3()
        publisher.publish_s3(s3, "example", "123456789012", body, objects)
        self.assertEqual(s3.calls[-1], "catalog.json")
        s3.calls.clear()
        publisher.publish_s3(s3, "example", "123456789012", body, objects)
        self.assertEqual(s3.calls, ["catalog.json"])
        local = Path(self.temp.name) / "output"
        publisher.publish_local(local, body, objects)
        self.assertEqual((local / loop["file"]).read_bytes(), b"one")

    def test_failed_or_mismatched_upload_does_not_publish_catalog(self):
        body, objects = publisher.prepare_library(self.source)
        first = next(iter(objects))
        s3 = FakeS3(fail=first)
        with self.assertRaises(RuntimeError):
            publisher.publish_s3(s3, "example", "123456789012", body, objects)
        self.assertNotIn("catalog.json", s3.objects)
        s3 = FakeS3()
        s3.objects[first] = {"body": b"bad", "metadata": {}}
        with self.assertRaises(ValueError):
            publisher.publish_s3(s3, "example", "123456789012", body, objects)
        self.assertNotIn("catalog.json", s3.objects)

    def test_rejects_path_traversal_and_duplicate_ids(self):
        self.catalog[0]["loops"][0]["file"] = "../loop.wav"
        self.write_catalog()
        with self.assertRaises(ValueError):
            publisher.prepare_library(self.source)
        self.catalog[0]["loops"][0]["file"] = "loop.wav"
        self.catalog[0]["loops"].append(dict(self.catalog[0]["loops"][0]))
        self.write_catalog()
        with self.assertRaises(ValueError):
            publisher.prepare_library(self.source)

    def test_build_never_removes_unmarked_custom_output(self):
        output = Path(self.temp.name) / "custom"
        stale = output / "Samples"
        stale.mkdir(parents=True)
        (output / ".nojekyll").touch()
        sentinel = stale / "personal.txt"
        sentinel.write_text("keep")
        old = os.environ.get("BREAKWATER_ASSET_BASE_URL")
        os.environ["BREAKWATER_ASSET_BASE_URL"] = "https://example.test/library/"
        try:
            with self.assertRaises(ValueError):
                build_web.build(output)
        finally:
            if old is None:
                os.environ.pop("BREAKWATER_ASSET_BASE_URL", None)
            else:
                os.environ["BREAKWATER_ASSET_BASE_URL"] = old
        self.assertEqual(sentinel.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()

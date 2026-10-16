#!/usr/bin/env python3
"""Publish a content-addressed sample library, or assemble one for local use."""
import argparse
import base64
import copy
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import shutil
from library_catalog import object_keys, source_catalog, source_path

ROOT = Path(__file__).resolve().parents[1]


def file_signature(stat):
    return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)


def prepare_library(source, previous=None, signatures=None):
    source = source.resolve()
    songs = json.loads((source / "catalog.json").read_text())
    if not isinstance(songs, list) or not songs:
        raise ValueError("The sample catalog is empty")
    manifest = copy.deepcopy(songs)
    objects = {}
    previous_paths = {}
    if previous is not None:
        try:
            _, previous_paths = source_catalog(previous)
        except ValueError:
            # One-time migration from the older playback-only catalog. Missing
            # local files still fail rather than guessing their identities.
            pass

    def object_path(relative):
        path = Path(source_path(relative))
        absolute = (source / path).resolve()
        if not absolute.is_relative_to(source):
            raise ValueError(f"Sample path is outside the library: {relative}")
        if not absolute.exists() and relative in previous_paths:
            return previous_paths[relative]
        if not absolute.is_file():
            raise FileNotFoundError(f"Missing source audio: {relative}")
        if absolute.suffix.lower() not in {".wav", ".m4a"}:
            raise ValueError(f"Unsupported audio format: {relative}")
        digest = hashlib.sha256()
        with absolute.open("rb") as stream:
            before = file_signature(os.fstat(stream.fileno()))
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
            after = file_signature(os.fstat(stream.fileno()))
        if before != after or file_signature(absolute.stat()) != after:
            raise ValueError(f"Source audio changed during hashing: {relative}")
        if signatures is not None:
            signatures[absolute] = after
        key = f"objects/{digest.hexdigest()}{absolute.suffix.lower()}"
        objects[key] = absolute
        return key

    ids = set()
    for song in manifest:
        if not song.get("loops"):
            raise ValueError("Each song must have loops")
        for loop in song["loops"]:
            if loop["id"] in ids:
                raise ValueError("Duplicate loop ID")
            ids.add(loop["id"])
            if "sourceFile" in loop:
                raise ValueError("sourceFile is reserved for the published manifest")
            loop["sourceFile"] = loop["file"]
            loop["file"] = object_path(loop["file"])
            if loop.get("parts"):
                if "sourceFiles" in loop["parts"]:
                    raise ValueError("sourceFiles is reserved for the published manifest")
                loop["parts"]["sourceFiles"] = list(loop["parts"]["files"])
                loop["parts"]["files"] = [object_path(p) for p in loop["parts"]["files"]]
    body = (json.dumps(manifest, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
    return body, objects


def publish_s3(s3, bucket, account, body, objects, *, previous=None, etag=None, expect_missing=False, before_commit=None):
    """Upload missing immutable objects before atomically publishing the catalog."""
    known = object_keys(previous) if previous is not None else set()
    def upload(item):
        key, path = item
        if key in known:
            return
        digest = Path(key).stem
        try:
            previous = s3.head_object(Bucket=bucket, Key=key, ExpectedBucketOwner=account)
        except Exception as error:
            response = getattr(error, "response", {})
            code = str(response.get("Error", {}).get("Code", ""))
            if code not in {"404", "NoSuchKey", "NotFound"}:
                raise
        else:
            if previous["ContentLength"] != path.stat().st_size or previous.get("Metadata", {}).get("sha256") != digest:
                raise ValueError(f"Existing immutable object does not match: {key}")
            return
        with path.open("rb") as stream:
            s3.put_object(
                Bucket=bucket, Key=key, Body=stream, ExpectedBucketOwner=account,
                ContentType=mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                CacheControl="public, max-age=31536000, immutable",
                Metadata={"sha256": digest},
                ChecksumSHA256=base64.b64encode(bytes.fromhex(digest)).decode(),
            )
    with ThreadPoolExecutor(max_workers=12) as workers:
        for count, _ in enumerate(workers.map(upload, objects.items()), 1):
            if count % 100 == 0:
                print(f"Prepared {count}/{len(objects)} audio objects", flush=True)
    if before_commit:
        before_commit()
    condition = {"IfMatch": etag} if etag is not None else ({"IfNoneMatch": "*"} if expect_missing else {})
    s3.put_object(Bucket=bucket, Key="catalog.json", Body=body, ExpectedBucketOwner=account,
                  ContentType="application/json", CacheControl="no-cache", **condition)


def publish_local(destination, body, objects):
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    for key, path in objects.items():
        target = destination / key
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            shutil.copy2(path, target)
    temporary = destination / "catalog.json.tmp"
    temporary.write_bytes(body)
    temporary.replace(destination / "catalog.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Samples")
    parser.add_argument("--local-output", type=Path, help="Build a local test library instead of uploading")
    args = parser.parse_args()
    if args.local_output:
        body, objects = prepare_library(args.source)
        publish_local(args.local_output, body, objects)
        print(f"Local asset library: {len(objects)} unique objects")
        return
    # Keep the old entry point safe for existing users: publication now goes
    # through the same conflict-checked workflow as the library command.
    from library import main as library_main
    library_main(["--source", str(args.source), "publish"])


if __name__ == "__main__":
    main()

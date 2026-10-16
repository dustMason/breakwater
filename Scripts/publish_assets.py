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

ROOT = Path(__file__).resolve().parents[1]


def prepare_library(source):
    source = source.resolve()
    songs = json.loads((source / "catalog.json").read_text())
    if not isinstance(songs, list) or not songs:
        raise ValueError("The sample catalog is empty")
    manifest = copy.deepcopy(songs)
    objects = {}

    def object_path(relative):
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"Unsafe sample path: {relative}")
        absolute = (source / path).resolve(strict=True)
        if not absolute.is_relative_to(source) or not absolute.is_file():
            raise ValueError(f"Sample path is outside the library: {relative}")
        if absolute.suffix.lower() not in {".wav", ".m4a"}:
            raise ValueError(f"Unsupported audio format: {relative}")
        digest = hashlib.sha256()
        with absolute.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
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
            loop["file"] = object_path(loop["file"])
            if loop.get("parts"):
                loop["parts"]["files"] = [object_path(p) for p in loop["parts"]["files"]]
    body = (json.dumps(manifest, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
    return body, objects


def publish_s3(s3, bucket, account, body, objects):
    """Upload missing immutable objects before atomically publishing the catalog."""
    def upload(item):
        key, path = item
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
    s3.put_object(Bucket=bucket, Key="catalog.json", Body=body, ExpectedBucketOwner=account,
                  ContentType="application/json", CacheControl="no-cache")


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
    body, objects = prepare_library(args.source)
    if args.local_output:
        publish_local(args.local_output, body, objects)
        print(f"Local asset library: {len(objects)} unique objects")
        return
    bucket = os.environ.get("BREAKWATER_ASSET_BUCKET")
    account = os.environ.get("BREAKWATER_AWS_ACCOUNT_ID")
    if not bucket or not account or not account.isdigit() or len(account) != 12:
        parser.error("Set BREAKWATER_ASSET_BUCKET and the 12-digit BREAKWATER_AWS_ACCOUNT_ID")
    import boto3
    session = boto3.Session(region_name=os.environ.get("BREAKWATER_AWS_REGION"))
    actual = session.client("sts").get_caller_identity()["Account"]
    if actual != account:
        raise RuntimeError("AWS credentials do not match BREAKWATER_AWS_ACCOUNT_ID")
    from botocore.config import Config
    s3 = session.client("s3", config=Config(max_pool_connections=16, retries={"max_attempts": 6}))
    publish_s3(s3, bucket, account, body, objects)
    print(f"Published catalog and {len(objects)} unique audio objects")


if __name__ == "__main__":
    main()

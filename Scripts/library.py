#!/usr/bin/env python3
"""Pull or publish Breakwater's editable sample catalog and audio library."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
from urllib.parse import urljoin
from urllib.request import Request, urlopen

from fetch_assets import base_url
from library_catalog import source_catalog, validate_source
from publish_assets import file_signature, prepare_library, publish_s3

ROOT = Path(__file__).resolve().parents[1]
CONFIG_KEYS = {"BREAKWATER_ASSET_BUCKET", "BREAKWATER_AWS_ACCOUNT_ID",
               "BREAKWATER_AWS_REGION", "BREAKWATER_ASSET_BASE_URL",
               "BREAKWATER_1PASSWORD_ITEM", "BREAKWATER_1PASSWORD_ACCOUNT"}


def load_config(path=ROOT / ".asset.env"):
    """Load only literal Breakwater settings, without executing shell code."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        words = shlex.split(line, comments=True)
        if not words:
            continue
        if words[0] == "export":
            words = words[1:]
        if len(words) != 1 or "=" not in words[0]:
            raise ValueError(".asset.env must contain simple KEY=value assignments")
        key, value = words[0].split("=", 1)
        if key not in CONFIG_KEYS:
            raise ValueError(".asset.env may contain only BREAKWATER asset settings")
        os.environ.setdefault(key, value)


def json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".catalog-", delete=False) as file:
            temporary = Path(file.name)
            file.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch_manifest(base):
    request = Request(urljoin(base_url(base), "catalog.json"), headers={"Cache-Control": "no-cache"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def pull(source, manifest):
    """Refresh an unmodified working catalog; never discard local edits."""
    source = Path(source)
    remote, remote_paths = source_catalog(manifest)
    validate_source(remote)
    path, base = source / "catalog.json", source / ".catalog-base.json"
    original = path.read_bytes() if path.exists() else None
    local = json.loads(original) if original is not None else None
    baseline = json.loads(base.read_bytes()) if base.exists() else None
    baseline_source, baseline_paths = source_catalog(baseline) if baseline is not None else (None, {})
    if local is not None and local != remote and (baseline_source is None or local != baseline_source):
        raise ValueError("Local catalog has unpublished edits. Back it up or publish/reconcile it before pulling.")
    # A metadata-only pull must not silently bless stale local audio as the new
    # baseline. Check only source paths whose published object actually changed.
    root = source.resolve()
    for relative, key in remote_paths.items():
        if baseline_paths.get(relative) == key:
            continue
        audio = (root / relative).resolve()
        if not audio.is_relative_to(root):
            raise ValueError("Local audio path leaves the sample library")
        if audio.exists():
            digest = hashlib.sha256()
            with audio.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != Path(key).stem:
                raise FileExistsError(f"Local audio differs from the published library: {relative}. Back it up before pulling.")
    if path.exists() and path.read_bytes() != original:
        raise ValueError("Local catalog changed while pulling; try again.")
    if local != remote:
        atomic_write(path, json_bytes(remote))
    atomic_write(base, json_bytes(manifest))
    return len(remote), sum(len(song["loops"]) for song in remote)


def without_source_paths(manifest):
    """Compare an older playback-only manifest with a migrated manifest."""
    result = json.loads(json.dumps(manifest))
    for song in result:
        for loop in song["loops"]:
            loop.pop("sourceFile", None)
            if loop.get("parts"):
                loop["parts"].pop("sourceFiles", None)
    return result


def publish(source, s3, bucket, account):
    """Publish changed objects and compare-and-swap the single manifest."""
    source = Path(source)
    path, base = source / "catalog.json", source / ".catalog-base.json"
    if not path.is_file():
        raise ValueError("No local catalog. Run './Scripts/library pull' first.")
    original = path.read_bytes()
    local = json.loads(original)
    validate_source(local)
    try:
        response = s3.get_object(Bucket=bucket, Key="catalog.json", ExpectedBucketOwner=account)
        with closing(response["Body"]) as stream:
            previous = json.load(stream)
        etag = response["ETag"]
    except Exception as error:
        code = str(getattr(error, "response", {}).get("Error", {}).get("Code", ""))
        if code not in {"404", "NoSuchKey", "NotFound"}:
            raise
        previous, etag = None, None
    signatures = {}
    body, objects = prepare_library(source, previous, signatures)
    candidate = json.loads(body)
    # The manifest must round-trip without losing any local metadata.
    candidate_source, _ = source_catalog(candidate)
    if candidate_source != local:
        raise ValueError("Catalog did not round-trip through the playback manifest")
    if previous is not None:
        try:
            source_catalog(previous)
        except ValueError:
            if without_source_paths(candidate) != previous:
                raise ValueError("The old published catalog differs from the local library; reconcile it before migration.")
        else:
            baseline = json.loads(base.read_bytes()) if base.exists() else None
            if candidate != previous and baseline != previous:
                raise ValueError("The published catalog changed since your last pull. Back up local edits, then reconcile them.")
    if candidate == previous:
        if path.read_bytes() != original:
            raise ValueError("Local catalog changed during publication; try again.")
        atomic_write(base, json_bytes(previous))
        return False, len(objects)

    # A source file or catalog changed during preparation must not be published
    # under a stale digest. The remote conditional write protects other editors.
    def check_local():
        if path.read_bytes() != original:
            raise ValueError("Local catalog changed during publication; try again.")
        for audio, expected in signatures.items():
            if file_signature(audio.stat()) != expected:
                raise ValueError("Source audio changed during publication; try again.")

    publish_s3(s3, bucket, account, body, objects, previous=previous, etag=etag,
               expect_missing=previous is None, before_commit=check_local)
    if path.read_bytes() == original:
        atomic_write(base, json_bytes(candidate))
    return True, len(objects)


def aws_session():
    """Use an optional 1Password item, otherwise the normal AWS provider chain."""
    try:
        import boto3
    except ImportError as error:
        raise RuntimeError("Install boto3 first: python3 -m pip install boto3") from error
    options = {"region_name": os.environ.get("BREAKWATER_AWS_REGION")}
    item = os.environ.get("BREAKWATER_1PASSWORD_ITEM")
    if item:
        command = ["op", "item", "get", item, "--format", "json"]
        if account := os.environ.get("BREAKWATER_1PASSWORD_ACCOUNT"):
            command += ["--account", account]
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            fields = {field.get("label"): field.get("value") for field in json.loads(result.stdout)["fields"]}
        except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as error:
            raise RuntimeError("Could not read the configured 1Password item. Unlock 1Password and check the item setting.") from error
        key = fields.get("AWS_ACCESS_KEY_ID") or fields.get("ACCESS_KEY_ID")
        secret = fields.get("AWS_SECRET_ACCESS_KEY") or fields.get("SECRET_ACCESS_KEY")
        if not key or not secret:
            raise ValueError("The 1Password item needs AWS access-key and secret-key fields")
        options.update(aws_access_key_id=key, aws_secret_access_key=secret)
        if token := fields.get("AWS_SESSION_TOKEN"):
            options["aws_session_token"] = token
    return boto3.Session(**options)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Samples", help="Local working library")
    parser.add_argument("action", choices=["pull", "publish"], help="Refresh the local catalog or publish local changes")
    args = parser.parse_args(argv)
    load_config()
    if args.action == "pull":
        songs, loops = pull(args.source, fetch_manifest(os.environ.get("BREAKWATER_ASSET_BASE_URL", "")))
        print(f"Catalog ready: {songs} folders, {loops} loops. Audio downloads separately when needed.")
        return
    bucket = os.environ.get("BREAKWATER_ASSET_BUCKET", "")
    account = os.environ.get("BREAKWATER_AWS_ACCOUNT_ID", "")
    if not bucket or len(account) != 12 or not account.isdigit():
        parser.error("Set BREAKWATER_ASSET_BUCKET and the 12-digit BREAKWATER_AWS_ACCOUNT_ID")
    session = aws_session()
    from botocore.config import Config
    if session.client("sts").get_caller_identity()["Account"] != account:
        raise RuntimeError("AWS credentials do not match BREAKWATER_AWS_ACCOUNT_ID")
    s3 = session.client("s3", config=Config(max_pool_connections=16, retries={"max_attempts": 6}))
    changed, objects = publish(args.source, s3, bucket, account)
    print(f"{'Published' if changed else 'Already current'}: {objects} locally available audio objects.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Library: {error}", file=sys.stderr)
        raise SystemExit(1)

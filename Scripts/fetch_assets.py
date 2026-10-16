#!/usr/bin/env python3
"""Restore the source audio files corresponding to the published catalog."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urljoin, urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
OBJECT = re.compile(r"objects/[0-9a-f]{64}\.(?:wav|m4a)\Z")


def base_url(value):
    parts = urlsplit(value)
    if (not parts.hostname or parts.username or parts.password or parts.query or parts.fragment
            or not (parts.scheme == "https" or (parts.scheme == "http" and
                    parts.hostname in {"localhost", "127.0.0.1", "::1"}))):
        raise ValueError("Set BREAKWATER_ASSET_BASE_URL to a valid HTTPS library URL")
    return value.rstrip("/") + "/"


def restore(source, base):
    source = source.resolve()
    local = json.loads((source / "catalog.json").read_text())
    with urlopen(urljoin(base, "catalog.json"), timeout=30) as response:
        published = json.load(response)
    if not isinstance(local, list) or len(local) != len(published):
        raise ValueError("Local and published catalogs differ; update the catalog before restoring")
    expected = copy.deepcopy(local)
    transfers = {}

    def register(relative, key):
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or not OBJECT.fullmatch(key):
            raise ValueError("Unsafe source or object path")
        destination = (source / path).resolve()
        if not destination.is_relative_to(source) or destination == source:
            raise ValueError("Source audio path leaves the sample library")
        if destination in transfers and transfers[destination] != key:
            raise ValueError("Conflicting source audio paths")
        transfers[destination] = key

    try:
        for local_song, remote_song in zip(expected, published):
            if len(local_song["loops"]) != len(remote_song["loops"]):
                raise ValueError("Loop counts differ")
            for local_loop, remote_loop in zip(local_song["loops"], remote_song["loops"]):
                register(local_loop["file"], remote_loop["file"])
                local_loop["file"] = remote_loop["file"]
                if local_loop.get("parts"):
                    local_paths, remote_paths = local_loop["parts"]["files"], remote_loop["parts"]["files"]
                    if len(local_paths) != len(remote_paths):
                        raise ValueError("Part counts differ")
                    for relative, key in zip(local_paths, remote_paths):
                        register(relative, key)
                    local_loop["parts"]["files"] = remote_paths
    except (KeyError, TypeError) as error:
        raise ValueError("Local and published catalogs differ") from error
    if expected != published:
        raise ValueError("Local and published catalogs differ; update the catalog before restoring")

    def digest(path):
        result = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                result.update(chunk)
        return result.hexdigest()

    # Check every existing file before writing anything; never overwrite local work.
    for path, key in transfers.items():
        if path.exists() and (not path.is_file() or digest(path) != Path(key).stem):
            raise FileExistsError(f"Existing local audio differs: {path.relative_to(source)}")

    count = 0
    for path, key in transfers.items():
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".breakwater-", delete=False) as output:
                temporary = Path(output.name)
                digest_value = hashlib.sha256()
                with urlopen(urljoin(base, key), timeout=90) as response:
                    for chunk in iter(lambda: response.read(1024 * 1024), b""):
                        digest_value.update(chunk)
                        output.write(chunk)
            if digest_value.hexdigest() != Path(key).stem:
                raise ValueError(f"Downloaded audio failed its integrity check: {key}")
            # Linking fails if another process created the destination.
            os.link(temporary, path)
            count += 1
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return count


if __name__ == "__main__":
    count = restore(ROOT / "Samples", base_url(os.environ.get("BREAKWATER_ASSET_BASE_URL", "")))
    print(f"Restored {count} audio files; existing matching files were left intact.")

"""Translate between the editable catalog and the public playback manifest."""
import copy
import math
import re
from pathlib import PurePosixPath

OBJECT = re.compile(r"objects/([0-9a-f]{64})\.(wav|m4a)\Z")


def validate_source(songs):
    """Reject malformed metadata before it reaches either player."""
    if not isinstance(songs, list) or not songs:
        raise ValueError("The source catalog is empty")
    song_ids, loop_ids = set(), set()
    def integer(value, low, high):
        return type(value) is int and low <= value <= high
    def waveform(values):
        return (isinstance(values, list) and len(values) >= 3 and
                all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and 0 <= v <= 1 for v in values))
    try:
        for song in songs:
            if not all(isinstance(song[k], str) and song[k] for k in ("id", "name", "artist", "sourceURL")):
                raise ValueError("A folder has incomplete metadata")
            if song["id"] in song_ids or not integer(song["sourceBPM"], 1, 1000) or not song["loops"]:
                raise ValueError("A folder has a duplicate ID, invalid tempo, or no loops")
            song_ids.add(song["id"])
            numbers = set()
            for loop in song["loops"]:
                ident, number = loop["id"], loop["number"]
                if not integer(ident, 0, 1023) or ident in loop_ids or not integer(number, 1, 9999) or number in numbers:
                    raise ValueError("A loop has an invalid or duplicate ID or number")
                loop_ids.add(ident); numbers.add(number)
                source_path(loop["file"])
                bars, beats, frames = loop["bars"], loop["beats"], loop["frames"]
                bpm = loop["bpm"]
                if (not integer(bars, 1, 10000) or beats != bars * 4 or not integer(frames, 1, 2**31 - 1)
                        or loop["sampleRate"] != 48000 or not isinstance(bpm, (int, float))
                        or isinstance(bpm, bool) or not math.isfinite(bpm)
                        or abs(bpm - 60 * beats * 48000 / frames) > 1e-6):
                    raise ValueError("A loop has invalid timing metadata")
                slices = loop["sliceFrames"]
                if (not isinstance(slices, list) or not slices or slices[0] != 0
                        or any(not integer(value, 0, frames - 1) for value in slices)
                        or slices != sorted(set(slices)) or not waveform(loop["waveform"])):
                    raise ValueError("A loop has invalid waveform or slice metadata")
                if not all(isinstance(loop[k], str) for k in ("sourceStart", "sourceEnd")):
                    raise ValueError("A loop has invalid source markers")
                if loop.get("parts"):
                    parts = loop["parts"]
                    if len(parts["files"]) != 4 or len(parts["waveforms"]) != 4 or not all(waveform(v) for v in parts["waveforms"]):
                        raise ValueError("A loop must have four valid part files and waveforms")
                    for path in parts["files"]:
                        source_path(path)
    except (KeyError, TypeError) as error:
        raise ValueError("The source catalog has incomplete or invalid metadata") from error


def source_path(value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("Invalid source audio path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in (".", "..") for part in value.split("/")):
        raise ValueError("Unsafe source audio path")
    if path.suffix.lower() not in {".wav", ".m4a"}:
        raise ValueError("Unsupported source audio format")
    return value


def source_catalog(manifest):
    """Return the editable catalog and source-path-to-object mapping.

    Source names are carried as extra fields in the same atomic playback
    manifest. Older clients ignore these fields.
    """
    if not isinstance(manifest, list) or not manifest:
        raise ValueError("The published catalog is empty")
    source = copy.deepcopy(manifest)
    paths = {}

    def remember(relative, key):
        relative = source_path(relative)
        match = OBJECT.fullmatch(key) if isinstance(key, str) else None
        if not match or PurePosixPath(relative).suffix.lower() != "." + match.group(2):
            raise ValueError("Invalid published audio object")
        if relative in paths and paths[relative] != key:
            raise ValueError("Conflicting objects for a source audio path")
        paths[relative] = key
        return relative

    try:
        for song in source:
            if not song["loops"]:
                raise ValueError("A published folder is empty")
            for loop in song["loops"]:
                loop["file"] = remember(loop.pop("sourceFile"), loop["file"])
                if loop.get("parts"):
                    parts = loop["parts"]
                    originals = parts.pop("sourceFiles")
                    if len(originals) != len(parts["files"]):
                        raise ValueError("Published part paths do not match")
                    parts["files"] = [remember(path, key) for path, key in zip(originals, parts["files"])]
    except (KeyError, TypeError) as error:
        raise ValueError("The published catalog lacks editable source paths; publish it once from the existing local library") from error
    return source, paths


def object_keys(manifest):
    """Return valid content-addressed audio keys from a playback manifest."""
    keys = set()
    for song in manifest:
        for loop in song["loops"]:
            for key in [loop["file"], *loop.get("parts", {}).get("files", [])]:
                if not isinstance(key, str) or not OBJECT.fullmatch(key):
                    raise ValueError("Invalid published audio object")
                keys.add(key)
    return keys

#!/usr/bin/env python3
"""Validate catalog metadata; optionally check a local working audio library."""
import argparse
import json
import math
from pathlib import Path
import wave

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--catalog", type=Path, default=root / "Tests/Fixtures/catalog.json")
parser.add_argument("--audio-root", type=Path, help="Also inspect referenced WAV files")
args = parser.parse_args()
songs = json.loads(args.catalog.read_text())
assert songs
seen = set()
for song in songs:
    assert song["loops"]
    for loop in song["loops"]:
        assert loop["id"] not in seen and 0 <= loop["id"] < 1024
        seen.add(loop["id"])
        assert loop["beats"] == loop["bars"] * 4
        assert abs(loop["bpm"] - 60 * loop["beats"] * 48000 / loop["frames"]) < 1e-6
        assert loop["sliceFrames"][0] == 0 and loop["sliceFrames"] == sorted(set(loop["sliceFrames"]))
        assert all(0 <= value < loop["frames"] for value in loop["sliceFrames"])
        assert len(loop["waveform"]) == 100 and all(math.isfinite(value) and 0 <= value <= 1 for value in loop["waveform"])
        if args.audio_root:
            with wave.open(str(args.audio_root / loop["file"])) as audio:
                assert audio.getnchannels() == 2 and audio.getframerate() == 48000 and audio.getsampwidth() == 3
                assert audio.getnframes() == loop["frames"]
                frames = audio.readframes(audio.getnframes())
                assert frames[:6] == frames[-6:] == bytes(6)
print(f"PASS: catalog metadata and {len(seen)} unique IDs" + ("; local WAVs verified" if args.audio_root else ""))

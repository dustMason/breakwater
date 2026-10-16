#!/usr/bin/env python3
"""Assemble a self-contained static site, without npm or a bundler."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> Path:
    output = output.resolve()
    # Never mix generated files with the working source tree.
    if output == ROOT or output == ROOT / "Web" or output == ROOT / "Samples":
        raise ValueError("Choose a separate output directory, such as build/web")
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cargo", "build", "--locked", "--release", "--target", "wasm32-unknown-unknown", "--target-dir", str(ROOT / "Rust/target"), "--manifest-path", str(ROOT / "Rust/Cargo.toml")], check=True, cwd=ROOT)
    shutil.copy2(ROOT / "Rust/target/wasm32-unknown-unknown/release/breakwater_audio.wasm", output / "breakwater_audio.wasm")
    # Retire the pre-port JavaScript DSP if this directory was built before.
    (output / "engine.js").unlink(missing_ok=True)
    for source in (ROOT / "Web").iterdir():
        if source.suffix in {".html", ".css", ".js", ".png"}:
            shutil.copy2(source, output / source.name)
    catalog = json.loads((ROOT / "Samples/catalog.json").read_text())
    previous_catalog = output / "Samples/catalog.json"
    def files(sample):
        return [sample["file"], *sample.get("parts", {}).get("files", [])]
    current_files = {path for song in catalog for sample in song["loops"] for path in files(sample)}
    if previous_catalog.exists():
        # A rebuild must also remove samples retired from the song library.
        for song in json.loads(previous_catalog.read_text()):
            for sample in song["loops"]:
                for path in files(sample):
                    relative = Path(path)
                    if relative.is_absolute() or ".." in relative.parts:
                        raise ValueError(f"Invalid previous sample path: {relative}")
                    if path not in current_files:
                        (output / "Samples" / relative).unlink(missing_ok=True)
    (output / "Samples").mkdir(exist_ok=True)
    shutil.copy2(ROOT / "Samples/catalog.json", output / "Samples/catalog.json")
    for song in catalog:
        for sample in song["loops"]:
            for path in files(sample):
                relative = Path(path)
                if relative.is_absolute() or ".." in relative.parts:
                    raise ValueError(f"Invalid sample path: {relative}")
                destination = output / "Samples" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / "Samples" / relative, destination)
    (output / ".nojekyll").touch()
    print(f"Static site: {output} ({sum(len(song['loops']) for song in catalog)} loops)")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/web")
    build(parser.parse_args().output)

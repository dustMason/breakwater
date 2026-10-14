#!/usr/bin/env python3
"""Assemble a self-contained static site, without npm or a bundler."""
import argparse
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> Path:
    output = output.resolve()
    # Never mix generated files with the working source tree.
    if output == ROOT or output == ROOT / "Web" or output == ROOT / "Samples":
        raise ValueError("Choose a separate output directory, such as build/web")
    output.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / "Web").iterdir():
        if source.suffix in {".html", ".css", ".js", ".png"}:
            shutil.copy2(source, output / source.name)
    catalog = json.loads((ROOT / "Samples/catalog.json").read_text())
    (output / "Samples").mkdir(exist_ok=True)
    shutil.copy2(ROOT / "Samples/catalog.json", output / "Samples/catalog.json")
    for song in catalog:
        for sample in song["loops"]:
            relative = Path(sample["file"])
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

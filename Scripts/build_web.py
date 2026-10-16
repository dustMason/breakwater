#!/usr/bin/env python3
"""Assemble the static player, with an externally configured asset library."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit

from publish_assets import prepare_library, publish_local

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path, local_assets=False) -> Path:
    output = output.resolve()
    if output == ROOT or output == ROOT / "Web" or output == ROOT / "Samples":
        raise ValueError("Choose a separate output directory, such as build/web")
    base = os.environ.get("BREAKWATER_ASSET_BASE_URL", "").strip()
    if local_assets:
        base = "./local-assets/"
    if not base:
        raise ValueError("Set BREAKWATER_ASSET_BASE_URL or use --local-assets")
    if not local_assets:
        parsed = urlsplit(base)
        if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError("BREAKWATER_ASSET_BASE_URL must be an HTTPS URL without credentials, a query, or a fragment")
        base = base.rstrip("/") + "/"
    output.mkdir(parents=True, exist_ok=True)
    # Remove generated audio from older self-contained builds. Only a marker
    # owned by this builder authorizes cleanup of a custom output directory.
    for name in ("Samples",) if local_assets else ("Samples", "local-assets"):
        stale = output / name
        if stale.exists() or stale.is_symlink():
            legacy_default = output == ROOT / "build/web" and (output / ".nojekyll").is_file()
            if not (output / ".breakwater-build").is_file() and not legacy_default:
                raise ValueError(f"Refusing to remove {stale} from an unmarked output directory")
            if stale.is_symlink():
                stale.unlink()
            else:
                shutil.rmtree(stale)
    subprocess.run(["cargo", "build", "--locked", "--release", "--target", "wasm32-unknown-unknown", "--target-dir", str(ROOT / "Rust/target"), "--manifest-path", str(ROOT / "Rust/Cargo.toml")], check=True, cwd=ROOT)
    shutil.copy2(ROOT / "Rust/target/wasm32-unknown-unknown/release/breakwater_audio.wasm", output / "breakwater_audio.wasm")
    (output / "engine.js").unlink(missing_ok=True)
    for source in (ROOT / "Web").iterdir():
        if source.suffix in {".html", ".css", ".js", ".png"}:
            shutil.copy2(source, output / source.name)
    if local_assets:
        body, objects = prepare_library(ROOT / "Samples")
        publish_local(output / "local-assets", body, objects)
    (output / "asset-config.json").write_text(json.dumps({"assetBaseURL": base}) + "\n")
    (output / ".nojekyll").touch()
    (output / ".breakwater-build").touch()
    print(f"Static site: {output}")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/web")
    parser.add_argument("--local-assets", action="store_true", help="Publish local sample files into the test build")
    args = parser.parse_args()
    build(args.output, local_assets=args.local_assets)

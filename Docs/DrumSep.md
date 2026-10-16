# DrumSep sample preparation

The Parts controls use the original [Iñaki Goyeneche DrumSep](https://github.com/inagoy/drumsep) Hybrid Demucs model, selected after comparing actual Breakwater loops with LarsNet and the former NMF layers. The part order is **Kick, Snare, Toms, Cymbals**; hi-hats are included in Cymbals. These are model estimates and can contain bleed or assign hand percussion to the closest kit category.

Separation runs offline. The iPad and browser load only prepared AAC files. Partial selections sum the selected estimates directly, without retaining a residual from the original recording. All four enabled continues to use the unmodified original, with smoothed transitions. The model and Python dependencies are not bundled in either application.

## Set up

Use Python 3.12 with an isolated environment and install ffmpeg/ffprobe. From the repository:

```sh
./Scripts/library pull             # Editable catalog, if not already present
python3 Scripts/fetch_assets.py    # Restore source audio when needed
uv venv build/parts-venv --python 3.12
uv pip install --python build/parts-venv/bin/python -r Scripts/requirements-parts.txt
mkdir -p build/models
build/parts-venv/bin/gdown 1-Dm666ScPkg8Gt2-lK3Ua0xOudWHZBGC -O build/models/49469ca8.th
build/parts-venv/bin/python Scripts/separate_parts.py
```

The download ID comes from the author's installer. The runner requires checkpoint SHA-256 `aefaa8543c9b9c75e22f5f32b53ab86dfe416457849af1383ff1aef83401423f` before safely loading the original `HDemucs` class. Keep the checkpoint in ignored `build/models`, or set `BREAKWATER_DRUMSEP_MODEL` / `--model` to a local copy. No audio is uploaded by this script.

## Regenerate and publish

```sh
# Optional: prepare a library outside the checkout.
build/parts-venv/bin/python Scripts/separate_parts.py --source /path/to/library --model /path/to/49469ca8.th
# After the initial migration, refresh selected stable IDs.
build/parts-venv/bin/python Scripts/separate_parts.py --ids 0 1 2
# Verify code safeguards and the prepared local library.
build/parts-venv/bin/python Tests/DrumSepPreparationTests.py
python3 Tests/PartsCatalogTests.py
```

The first migration requires all loops of each selected song, since labels belong to a whole song. Later runs skip a loop only when its source, recipe, and all four encoded-file hashes match. A small per-loop `parts.json` receipt also lets an interrupted batch resume before the catalog has been published. `--force` recomputes; `--threads` controls CPU inference threads per worker (default four). `--jobs` starts independent worker processes (default one), each loading its own checkpoint. For a larger machine, `--jobs 4 --threads 2` uses up to eight inference threads and requires memory for four model instances.

New files are written beneath `Stems/drumsep-v1`, with content hashes in their filenames. Existing NMF files and source WAVs are retained. Once every selected output is validated, the local catalog is atomically replaced. If the original audio or catalog changed during processing, publication aborts rather than overwriting concurrent curation. Publish the new stems with `./Scripts/library publish`; a local build can use `Scripts/build_web.py --local-assets`. The publisher uploads immutable objects before replacing the remote catalog. Do not commit the model or generated audio.

## Audio behavior and provenance

Inputs are stereo 48 kHz WAVs. Inference uses the original 44.1 kHz model, one shift, 25% overlap, and seed zero independently per loop. Outputs are resampled and fitted to the exact original frame count. There is no time stretch, extra musical context, or per-stem normalization. When needed, one gain reduction is applied to all four stems together for headroom; FFmpeg AAC decoding is checked for overshoot. AAC decoders can produce different peaks, and stem combinations and filters still require playback headroom. Catalog waveform previews reflect the FFmpeg-decoded prepared files.

AAC remains stereo 48 kHz / 160 kbps with exact container duration, matching both players. `parts.separation` records the recipe, checkpoint hash, source hash, encoded hashes, shared gain, and decoded peak; existing readers ignore this additional metadata. Stable loop IDs, original timing, transient slices, and original waveform data are preserved.

The upstream repository code is MIT. A separate public commercial redistribution grant for the externally hosted weights was not found; see [the author's integration discussion](https://github.com/inagoy/drumsep/issues/9). Keep the weight download separate from the app. Existing recording/sample rights continue to apply.

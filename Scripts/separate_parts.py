#!/usr/bin/env python3
"""Prepare four DrumSep parts offline; publish the catalog only after validation.

Requires Scripts/requirements-parts.txt, ffmpeg, ffprobe, and the original
49469ca8.th checkpoint. Originals are read-only. No network access at runtime.
"""
import argparse
import concurrent.futures
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import random
import subprocess
import tempfile

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
PARTS = ('Kick', 'Snare', 'Toms', 'Cymbals')
SOURCES = ('bombo', 'redoblante', 'toms', 'platillos')
MODEL_SHA256 = 'aefaa8543c9b9c75e22f5f32b53ab86dfe416457849af1383ff1aef83401423f'
RECIPE = {'method': 'drumsep', 'version': 1, 'model': '49469ca8',
          'modelSHA256': MODEL_SHA256, 'sampleRate': 44100, 'seed': 0,
          'shifts': 1, 'overlap': 0.25, 'codec': 'aac', 'bitrate': '160k',
          'peakCeiling': 0.98, 'aacRetryCeiling': 0.9,
          'torch': '2.6.0', 'torchaudio': '2.6.0', 'demucs': '4.0.1'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_path(root, relative):
    path = (root / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(root.resolve()):
        raise ValueError(f'Path is outside the sample library: {relative}')
    return path


def select_samples(catalog, ids):
    all_ids = [sample['id'] for song in catalog for sample in song['loops']]
    if len(all_ids) != len(set(all_ids)):
        raise ValueError('Duplicate sample IDs')
    chosen = set(all_ids if ids is None else ids)
    if not chosen or chosen - set(all_ids):
        raise ValueError('Select at least one valid sample ID')
    for song in catalog:
        song_ids = {s['id'] for s in song['loops']}
        if song_ids & chosen and song.get('partLabels') != list(PARTS) and not song_ids <= chosen:
            raise ValueError(f"First DrumSep migration must include every loop in {song['name']}; song-wide labels cannot mix NMF and DrumSep parts")
    return [s for song in catalog for s in song['loops'] if s['id'] in chosen]


def cached_parts(root, sample, source_hash):
    parts = sample.get('parts', {})
    provenance = parts.get('separation', {})
    if provenance.get('recipe') != RECIPE or provenance.get('sourceSHA256') != source_hash:
        return None
    files, hashes, waves = parts.get('files', []), provenance.get('fileSHA256', []), parts.get('waveforms', [])
    if not (len(files) == len(hashes) == len(waves) == 4):
        return None
    if any(len(w) != len(sample['waveform']) or not np.isfinite(w).all()
           or any(v < 0 or v > 1 for v in w) for w in waves):
        return None
    try:
        if all(source_path(root, file).is_file() and digest(source_path(root, file)) == sha
               for file, sha in zip(files, hashes)):
            return parts
    except (OSError, ValueError):
        pass
    return None


def receipt_path(root, sample):
    return root / 'Stems' / 'drumsep-v1' / str(sample['id']) / 'parts.json'


def read_receipt(root, sample, source_hash):
    try:
        candidate = dict(sample, parts=json.loads(receipt_path(root, sample).read_text()))
        return cached_parts(root, candidate, source_hash)
    except (OSError, ValueError, TypeError, KeyError):
        return None


def write_receipt(root, sample, parts):
    path = receipt_path(root, sample)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.receipt-', delete=False) as temp:
        json.dump(parts, temp)
        temporary = Path(temp.name)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def load_separator(checkpoint, threads):
    import torch
    import torchaudio
    from importlib.metadata import version
    from demucs.hdemucs import HDemucs
    from demucs.states import load_model
    from demucs.apply import apply_model
    if digest(checkpoint) != MODEL_SHA256:
        raise ValueError('Checkpoint SHA-256 does not match the original auditioned DrumSep model')
    for package in ('torch', 'torchaudio', 'demucs'):
        if version(package).split('+')[0] != RECIPE[package]:
            raise ValueError(f'Install Scripts/requirements-parts.txt: expected {package} {RECIPE[package]}')
    torch.set_num_threads(threads)
    with torch.serialization.safe_globals([HDemucs]):
        package = torch.load(checkpoint, map_location='cpu', weights_only=True)
    model = load_model(package).cpu().eval()
    if set(model.sources) != set(SOURCES) or model.samplerate != 44100 or model.audio_channels != 2:
        raise ValueError('Unexpected DrumSep model shape or source names')

    def separate(audio, rate):
        # Seed each loop independently so --ids and resumed runs produce the same result.
        torch.manual_seed(RECIPE['seed'])
        random.seed(RECIPE['seed'])
        x = torchaudio.functional.resample(torch.from_numpy(audio.T.copy()), rate, model.samplerate)
        ref = x.mean(0)
        mean, std = ref.mean(), ref.std()
        if float(std) < 1e-8:
            return np.zeros((4, len(audio), 2), dtype=np.float32)
        with torch.inference_mode():
            stems = apply_model(model, ((x - mean) / std)[None], device='cpu', shifts=1,
                                split=True, overlap=0.25, progress=False)[0] * std + mean
            stems = stems[[model.sources.index(s) for s in SOURCES]]
            stems = torchaudio.functional.resample(stems, model.samplerate, rate)
            stems = torch.nn.functional.pad(stems, (0, max(0, len(audio) - stems.shape[-1])))
        result = stems[..., :len(audio)].permute(0, 2, 1).numpy()
        if result.shape != (4, len(audio), 2) or not np.isfinite(result).all():
            raise ValueError('Invalid DrumSep output')
        return result
    return separate


def encode_parts(root, sample, stems, source_hash):
    """Use one shared gain, including AAC overshoot, and retain exact container duration."""
    target = root / 'Stems' / 'drumsep-v1' / str(sample['id'])
    target.mkdir(parents=True, exist_ok=True)
    gain = min(1.0, RECIPE['peakCeiling'] / max(float(np.max(np.abs(stems))), 1e-12))
    with tempfile.TemporaryDirectory(prefix='.encode-', dir=target) as temporary:
        temporary = Path(temporary)
        decoded = []
        for attempt in range(8):
            decoded = []
            for index, stem in enumerate(stems):
                path = temporary / f'{index}.m4a'
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', '48000', '-ac', '2',
                                '-i', 'pipe:0', '-c:a', 'aac', '-b:a', '160k', '-movie_timescale', '48000',
                                '-movflags', '+faststart', str(path)],
                               input=np.asarray(stem * gain, dtype='<f4').tobytes(), check=True)
                info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'a:0',
                    '-show_entries', 'stream=sample_rate,channels,duration_ts,time_base', '-of', 'json', str(path)]))['streams'][0]
                if (info['sample_rate'], info['channels'], info['time_base'], info['duration_ts']) != ('48000', 2, '1/48000', sample['frames']):
                    raise ValueError(f'Encoded format/duration mismatch: {path}')
                raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-acodec', 'pcm_f32le', 'pipe:1'])
                y = np.frombuffer(raw, dtype='<f4').reshape(-1, 2)
                if len(y) < sample['frames'] or not np.isfinite(y).all():
                    raise ValueError(f'Invalid AAC decode: {path}')
                decoded.append(y[:sample['frames']])
            peak = max(float(np.max(np.abs(y))) for y in decoded)
            if peak <= 1.0:
                break
            # AAC quantization is nonlinear: tiny gain changes can retain an
            # overshoot. Leave appreciable headroom on each retry.
            gain *= RECIPE['aacRetryCeiling'] / peak
        else:
            raise ValueError('Unable to encode parts without full-scale overshoot')
        files, hashes, waves = [], [], []
        for index, y in enumerate(decoded):
            path = temporary / f'{index}.m4a'
            sha = digest(path)
            destination = target / f'{index}-{PARTS[index].lower()}-{sha}.m4a'
            if destination.exists() and digest(destination) != sha:
                raise ValueError(f'Existing immutable stem is corrupt: {destination}')
            if not destination.exists():
                path.replace(destination)
            files.append(str(destination.relative_to(root)))
            hashes.append(sha)
            waves.append([round(float(np.max(np.abs(chunk))), 5) if len(chunk) else 0
                          for chunk in np.array_split(y, len(sample['waveform']))])
    return {'files': files, 'waveforms': waves,
            'separation': {'recipe': RECIPE, 'sourceSHA256': source_hash, 'fileSHA256': hashes,
                           'gain': gain, 'decodedPeak': peak}}


def initialize_worker(checkpoint, threads, root):
    global worker_separate, worker_root
    worker_separate = load_separator(checkpoint, threads)
    worker_root = root


def prepare_sample(sample, source_hash):
    audio, sr = sf.read(source_path(worker_root, sample['file']), dtype='float32', always_2d=True)
    if sr != 48000 or audio.shape != (sample['frames'], 2) or not np.isfinite(audio).all():
        raise ValueError(f"Unexpected original format: {sample['file']}")
    parts = encode_parts(worker_root, sample, worker_separate(audio, sr), source_hash)
    write_receipt(worker_root, sample, parts)
    return sample['id'], parts


def publish_catalog(path, expected_bytes, catalog, results, root, source_hashes):
    # Recheck every input and the catalog to avoid overwriting concurrent curation.
    for relative, sha in source_hashes.items():
        if digest(source_path(root, relative)) != sha:
            raise RuntimeError(f'Source changed during separation: {relative}; catalog was not published')
    if path.read_bytes() != expected_bytes:
        raise RuntimeError('Catalog changed during separation; rerun against the new catalog')
    for song in catalog:
        if any(s['id'] in results for s in song['loops']):
            song['partLabels'] = list(PARTS)
        for sample in song['loops']:
            if sample['id'] in results:
                sample['parts'] = results[sample['id']]
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.catalog-', suffix='.json', delete=False) as temp:
        json.dump(catalog, temp, indent=2)
        temp.write('\n')
        temporary = Path(temp.name)
    try:
        if path.read_bytes() != expected_bytes:
            raise RuntimeError('Catalog changed before publication; rerun against the new catalog')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'Samples', help='Source library containing catalog.json')
    parser.add_argument('--model', type=Path, default=Path(os.environ.get('BREAKWATER_DRUMSEP_MODEL', ROOT / 'build/models/49469ca8.th')))
    parser.add_argument('--threads', type=int, default=4, help='CPU inference threads per worker')
    parser.add_argument('--jobs', type=int, default=1, help='Independent worker processes, each holding a model and using --threads CPU threads')
    parser.add_argument('--ids', nargs='+', type=int, help='Only regenerate these IDs; first migration requires whole songs')
    parser.add_argument('--force', action='store_true', help='Recompute even when source, recipe, and stem hashes match')
    args = parser.parse_args()
    if args.threads < 1 or args.jobs < 1:
        parser.error('--threads and --jobs must be positive')
    root = args.source.resolve()
    catalog_path = root / 'catalog.json'
    original = catalog_path.read_bytes()
    catalog = json.loads(original)
    selected = select_samples(catalog, args.ids)
    hashes = {s['file']: digest(source_path(root, s['file'])) for s in selected}
    results, pending = {}, []
    for sample in selected:
        sha = hashes[sample['file']]
        parts = None if args.force else cached_parts(root, sample, sha)
        if parts is None and not args.force:
            parts = read_receipt(root, sample, sha)
        if parts is None:
            pending.append((sample, sha))
        else:
            results[sample['id']] = parts
            print(f"{len(results)}/{len(selected)}: loop {sample['id']} cached", flush=True)

    def completed(result):
        ident, parts = result
        results[ident] = parts
        print(f"{len(results)}/{len(selected)}: loop {ident} generated", flush=True)

    if pending and args.jobs == 1:
        initialize_worker(args.model, args.threads, root)
        for sample, sha in pending:
            completed(prepare_sample(sample, sha))
    elif pending:
        with concurrent.futures.ProcessPoolExecutor(max_workers=min(args.jobs, len(pending)),
                mp_context=multiprocessing.get_context('spawn'), initializer=initialize_worker,
                initargs=(args.model, args.threads, root)) as pool:
            futures = [pool.submit(prepare_sample, sample, sha) for sample, sha in pending]
            for future in concurrent.futures.as_completed(futures):
                completed(future.result())
    publish_catalog(catalog_path, original, catalog, results, root, hashes)
    print(f'Published {len(selected)} loops with Kick / Snare / Toms / Cymbals. Originals unchanged.')


if __name__ == '__main__':
    main()

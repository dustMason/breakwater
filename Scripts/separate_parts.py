#!/usr/bin/env python3
"""Approximate drum parts with per-loop nonnegative spectrogram factorization.

The output masks partition the complex stereo spectrogram, preserving phase and
loop length. Names are deliberately descriptive rather than instrument claims.
Requires numpy, scipy, soundfile and ffmpeg for offline preparation only.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import warnings

os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
os.environ.setdefault('VECLIB_MAXIMUM_THREADS', '1')
import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
PARTS = ('Low', 'Body', 'Attack', 'High')
NFFT, HOP, RANK, ITERATIONS = 2048, 512, 8, 42


def separate(sample):
    source = ROOT / 'Samples' / sample['file']
    audio, sr = sf.read(source, dtype='float32', always_2d=True)
    if sr != 48000 or audio.shape != (sample['frames'], 2):
        raise ValueError(f'Unexpected audio format: {source}')
    # Wrap padding makes analysis continuous across the loop boundary.
    padded = np.pad(audio, ((NFFT, NFFT), (0, 0)), mode='wrap')
    specs = [signal.stft(padded[:, ch], fs=sr, nperseg=NFFT, noverlap=NFFT-HOP,
                         boundary='zeros', padded=True)[2] for ch in range(2)]
    magnitude = np.sqrt((np.abs(specs[0]) ** 2 + np.abs(specs[1]) ** 2) * .5).astype('float32')
    # Whiten frequencies so quiet high percussion can form its own component.
    weight = np.maximum(np.mean(magnitude, axis=1, keepdims=True), 1e-6) ** .5
    v = magnitude / weight
    rng = np.random.default_rng(sample['id'] + 17)
    w = rng.random((v.shape[0], RANK), dtype=np.float32) + .1
    h = rng.random((RANK, v.shape[1]), dtype=np.float32) + .1
    eps = 1e-8
    for _ in range(ITERATIONS):
        h *= (w.T @ v) / (w.T @ w @ h + eps)
        w *= (v @ h.T) / (w @ (h @ h.T) + eps)
        norm = np.maximum(w.sum(axis=0), eps)
        w /= norm
        h *= norm[:, None]
    templates = w * weight
    frequencies = np.fft.rfftfreq(NFFT, 1 / sr)
    centroids = (templates.T @ frequencies) / np.maximum(templates.sum(axis=0), eps)
    order = np.argsort(centroids)
    components = np.empty(RANK, dtype=np.int32)
    for group, pair in enumerate(np.array_split(order, len(PARTS))):
        components[pair] = group
    energies = np.stack([templates[:, components == group] @ h[components == group] for group in range(len(PARTS))])
    masks = energies / np.maximum(energies.sum(axis=0, keepdims=True), eps)
    if not np.isfinite(masks).all():
        raise ValueError(f'Non-finite analysis masks: {source}')
    paths, waveforms = [], []
    base = f"Stems/{Path(sample['file']).stem}"
    for group, name in enumerate(PARTS):
        channels = []
        for spec in specs:
            _, y = signal.istft(spec * masks[group], fs=sr, nperseg=NFFT, noverlap=NFFT-HOP,
                                input_onesided=True, boundary=True)
            channels.append(y[NFFT:NFFT + len(audio)])
        stem = np.stack(channels, axis=1).astype('float32')
        if len(stem) != len(audio):
            raise ValueError(f'Stem length mismatch: {source}')
        path = f'{base}-{group}.m4a'
        destination = ROOT / 'Samples' / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = destination.with_suffix('.tmp.m4a')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'f32le', '-ar', str(sr),
                        '-ac', '2', '-i', 'pipe:0', '-c:a', 'aac', '-b:a', '160k', '-movie_timescale', '48000', '-movflags', '+faststart', str(temp)],
                       input=stem.tobytes(), check=True)
        temp.replace(destination)
        paths.append(path)
        waveform = [float(np.max(np.abs(chunk))) if len(chunk) else 0 for chunk in np.array_split(stem, len(sample['waveform']))]
        waveforms.append([round(x, 5) for x in waveform])
    return sample['id'], paths, waveforms


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--ids', nargs='*', type=int, help='Only analyze these sample IDs (for audition/development)')
    args = parser.parse_args()
    catalog_path = ROOT / 'Samples/catalog.json'
    catalog = json.loads(catalog_path.read_text())
    selected = [s for song in catalog for s in song['loops'] if args.ids is None or s['id'] in args.ids]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(separate, s) for s in selected]
        results = {}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            ident, paths, waveforms = future.result()
            results[ident] = {'files': paths, 'waveforms': waveforms}
            print(f'{i}/{len(selected)}: loop {ident}', flush=True)
    for song in catalog:
        song['partLabels'] = list(PARTS)
        for sample in song['loops']:
            if sample['id'] in results:
                sample['parts'] = results[sample['id']]
    catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')

if __name__ == '__main__':
    main()

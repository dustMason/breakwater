#!/usr/bin/env python3
"""Verify every shipped layer's duration, channels and waveform metadata."""
import concurrent.futures
import hashlib
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / 'Samples/catalog.json').read_text())
checks = []
for song in catalog:
    assert song['partLabels'] == ['Kick', 'Snare', 'Toms', 'Cymbals']
    for sample in song['loops']:
        parts = sample['parts']
        separation = parts['separation']
        assert separation['recipe']['method'] == 'drumsep'
        assert separation['recipe']['model'] == '49469ca8'
        assert separation['recipe']['modelSHA256'] == 'aefaa8543c9b9c75e22f5f32b53ab86dfe416457849af1383ff1aef83401423f'
        assert separation['sourceSHA256'] == hashlib.sha256((ROOT / 'Samples' / sample['file']).read_bytes()).hexdigest()
        assert 0 < separation['gain'] <= 1 and 0 <= separation['decodedPeak'] <= 1
        assert len(parts['files']) == len(parts['waveforms']) == 4
        assert all(len(wave) == len(sample['waveform']) and all(math.isfinite(v) and 0 <= v <= 1 for v in wave) for wave in parts['waveforms'])
        assert len(separation['fileSHA256']) == 4
        for name, sha in zip(parts['files'], separation['fileSHA256']):
            path = Path(name)
            assert not path.is_absolute() and '..' not in path.parts
            assert hashlib.sha256((ROOT / 'Samples' / path).read_bytes()).hexdigest() == sha
            checks.append((ROOT / 'Samples' / path, sample['frames']))
assert len(checks) == len(set(path for path, _ in checks)) == 888

def check(item):
    path, frames = item
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
        'stream=sample_rate,channels,duration_ts,time_base', '-of', 'json', str(path)]))['streams'][0]
    assert info['sample_rate'] == '48000' and info['channels'] == 2, path
    assert info['time_base'] == '1/48000' and info['duration_ts'] == frames, (path, info, frames)
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    list(pool.map(check, checks))
print(f'PASS {len(catalog)} songs, {len(checks)} stereo parts with exact loop durations and finite waveforms')

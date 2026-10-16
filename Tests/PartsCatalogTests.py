#!/usr/bin/env python3
"""Verify every shipped layer's duration, channels and waveform metadata."""
import concurrent.futures
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / 'Samples/catalog.json').read_text())
checks = []
for song in catalog:
    assert song['partLabels'] == ['Low', 'Body', 'Attack', 'High']
    for sample in song['loops']:
        parts = sample['parts']
        assert len(parts['files']) == len(parts['waveforms']) == 4
        assert all(len(wave) == len(sample['waveform']) and all(math.isfinite(v) and 0 <= v <= 1 for v in wave) for wave in parts['waveforms'])
        for name in parts['files']:
            path = Path(name)
            assert not path.is_absolute() and '..' not in path.parts
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

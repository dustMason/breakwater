#!/usr/bin/env python3
"""Validate shipped audio metadata independently of the app's importer."""
from pathlib import Path
import json,struct,wave
r=Path(__file__).resolve().parents[1];songs=json.loads((r/'Samples/catalog.json').read_text());seen=set()
assert len(songs)==2
for song in songs:
 assert len(song['loops'])==30
 for loop in song['loops']:
  assert loop['id'] not in seen;seen.add(loop['id'])
  with wave.open(str(r/'Samples'/loop['file'])) as f:
   assert f.getnchannels()==2 and f.getframerate()==48000 and f.getsampwidth()==3
   assert f.getnframes()==loop['frames'];frames=f.readframes(f.getnframes())
   assert frames[:6]==frames[-6:]==bytes(6)
  assert abs(loop['bpm']-60*loop['beats']*48000/loop['frames'])<1e-6
  assert loop['sliceFrames'][0]==0 and loop['sliceFrames']==sorted(set(loop['sliceFrames']))
  assert all(0<=s<loop['frames'] for s in loop['sliceFrames'])
  assert len(loop['waveform'])==100 and all(0<=x<=1 for x in loop['waveform'])
assert seen==set(range(60))
print('PASS: all 60 bundled WAVs, stable IDs, source timing, beat counts, waveform data, and transient markers')

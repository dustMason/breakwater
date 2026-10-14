#!/usr/bin/env python3
"""Import the existing WAV packs and derive waveform / transient landmarks.
Requires numpy scipy soundfile librosa, only for regenerating the catalog.
Runtime app has no Python dependencies.
"""
import argparse,csv,json,shutil
from pathlib import Path
import numpy as np, scipy.signal as sig, soundfile as sf, librosa
p=argparse.ArgumentParser();p.add_argument('packs',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[1];out=root/'Samples';out.mkdir(exist_ok=True)
existing=json.loads((out/'catalog.json').read_text()) if (out/'catalog.json').exists() else []
songs=[]
for name,prefix,source in [('Sangandongo','sg','https://www.youtube.com/watch?v=hTAdzPG4iNQ'),('Malanga','ml','https://www.youtube.com/watch?v=houWewbo9yc')]:
 folder=args.packs/f'Niagara - {name} Drum Loops';target=out/name;target.mkdir(exist_ok=True);loops=[]
 for row in csv.DictReader((folder/'Loop Index.csv').open()):
  n=int(row['loop']);src=folder/row['file'];filename=f'{name}/{prefix}{n:02d}.wav';shutil.copyfile(src,out/filename)
  y,sr=sf.read(src,always_2d=True);mono=y.mean(axis=1);duration=len(y)/sr
  a=librosa.resample(mono,orig_sr=sr,target_sr=22050)
  env=librosa.onset.onset_strength(y=a,sr=22050,hop_length=128,n_fft=1024)
  peaks,_=sig.find_peaks(env,distance=round(.055*22050/128),prominence=max(.4,float(np.percentile(env,75))*.45))
  times=librosa.frames_to_time(peaks,sr=22050,hop_length=128)-.012
  cuts=[0]
  # Keep attacks intact and remove excessively short slices / the trailing boundary.
  for t in times:
   frame=max(0,round(t*sr))
   if frame-cuts[-1]>=.055*sr and len(y)-frame>.035*sr:cuts.append(frame)
  waveform=[round(float(np.max(abs(b))),5) for b in np.array_split(y,100)]
  loops.append({'id':len(songs)*30+n-1,'number':n,'file':filename,'bars':int(row['bars_4_4']),'beats':int(row['beats']),'bpm':float(row['average_bpm']),'frames':len(y),'sampleRate':sr,'sourceStart':row['source_start'],'sourceEnd':row['source_end'],'waveform':waveform,'sliceFrames':cuts})
 songs.append({'id':prefix,'name':name,'artist':'Niagara','sourceBPM':round(float(np.median([l['bpm'] for l in loops]))),'sourceURL':source,'loops':loops})
 print(name,len(loops),'loops;',sum(len(l['sliceFrames']) for l in loops),'transient slices')
# Preserve later sample packs and their persistent IDs when refreshing Niagara.
songs.extend(song for song in existing if song['id'] not in {'sg','ml'})
(out/'catalog.json').write_text(json.dumps(songs,indent=2)+'\n')

# Breakwater sample library

258 stereo 48 kHz / 24-bit PCM WAV loops across 14 song pages. The initial 60 Niagara loops retain their original files and IDs (0–59). The October 14 percussion expedition adds 198 loops with IDs 60–257.

These are decoded exports of lossy YouTube streams, not lossless masters. Audio rights remain with their respective owners; the application source does not grant a separate sample license.

## Original packs

- **Sangandongo** — 30 loops from 12:00–14:00, approximately 105 BPM. [Recording](https://www.youtube.com/watch?v=hTAdzPG4iNQ).
- **Malanga** — 30 loops across the performance, approximately 150 BPM. [Recording](https://www.youtube.com/watch?v=houWewbo9yc).

## Percussion expedition

| Source | Loops | Approx. BPM | Source audio |
|---|---:|---:|---|
| Julian Sartorius — Locked Groove 022 | 6 | 133 | [Recording](https://www.youtube.com/watch?v=m31dT-P7ADU) |
| Bumps — A Safe Balm | 18 | 132 | [Recording](https://www.youtube.com/watch?v=JRw1a9_jZR4) |
| Guem & Zaka Percussion — Le Serpent | 18 | 128 | [Recording](https://www.youtube.com/watch?v=FaAWReBMLC0) |
| Guem & Zaka Percussion — L'abeille | 18 | 115 | [Recording](https://www.youtube.com/watch?v=YvhXCbeQ5Go) |
| Jlin & Third Coast Percussion — Perspective: III. Derivative | 18 | 161 | [Recording](https://www.youtube.com/watch?v=RTpRrvlPyF8) |
| Steve Reich & Third Coast Percussion — Music for Pieces of Wood | 18 | 139 | [Recording](https://www.youtube.com/watch?v=DVV_D7EPPB4) |
| Doudou N’Diaye Rose — Rose Rhythm | 18 | 134 | [Recording](https://www.youtube.com/watch?v=bSxVJ06j9FI) |
| Okay Temiz — Penguin | 18 | 89 | [Recording](https://www.youtube.com/watch?v=wRuksYr1J0E) |
| John Cage & Third Coast Percussion — Third Construction | 12 | 159 | [Recording](https://www.youtube.com/watch?v=6jyoD-ZYSmw) |
| Valentina Magaletti & Julian Sartorius — Sobaka | 18 | 121 | [Recording](https://www.youtube.com/watch?v=3YLmlkUojF8) |
| Bumps — Biotic Discussion | 18 | 126 | [Recording](https://www.youtube.com/watch?v=qdFC1eIBAMs) |
| Bumps — Can You See? | 18 | 158 | [Recording](https://www.youtube.com/watch?v=57klyQWXC1U) |

BPM is measured per cut from its frame length and assigned beat count. Page BPM is the median of that page's loops. Four-pulse bars are a sampling convention for live and polyrhythmic material, not a statement about the original score. Third Construction includes changing, asymmetrical textures (approximately 127–199 interpreted BPM); use the per-pad BPM as the reference. Locked Groove 022 is one repeated 1.8-second performance: its six pads are two entry phases at 1-, 2- and 4-bar lengths.

New cuts follow detected transient entries and score neighboring rhythm/phrase similarity. They keep the recording's original pitch and internal timing, with no quantization, time stretch, EQ or compression. Each track receives only a common gain reduction if needed to keep peaks below -1 dBFS; raised-cosine edge fades are 0.75 ms in / 3 ms out. WAV sampler markers span the whole file.

`catalog.json` includes stable IDs, source timestamps, measured BPM, frame/beat counts, waveform envelopes and transient indices. `Expedition/sources.json` lists source recordings and timing caveats; `Expedition/validation.json` records hashes, PCM lengths, levels and seam checks. All new WAVs pass decode/format/boundary checks. These remain audition candidates: they have not had a human listening pass.

The native app supports Tape and Slice modes. The browser uses whole-loop pitch/rate scaling and downloads only selected loops, caching them for the visit. Only the trimmed WAVs and catalog ship in the Pages artifact. Source recordings, MP3 reels and OP-1 patches are in the separate sample dumps.

`Scripts/prepare_samples.py` refreshes the original Niagara packs while preserving subsequent catalog entries and IDs. The catalog is already prepared; no Python audio-analysis dependencies are needed to build or run the app.

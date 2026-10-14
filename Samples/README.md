# Niagara sample library

60 stereo 48 kHz / 24-bit PCM WAV loops, copied unchanged from Jordan's existing sampling packs on 2026-10-14. These are decoded exports of lossy YouTube Opus recordings, not lossless masters. This repository is private.

- **Sangandongo** — 30 loops from 12:00–14:00, approximately 105 BPM. Source: https://www.youtube.com/watch?v=hTAdzPG4iNQ
- **Malanga** — 30 loops spread across the performance, approximately 150 BPM. Source: https://www.youtube.com/watch?v=houWewbo9yc

Both uploads identify Niagara and M. i. G. - music. Audio rights remain with their respective owners; the application source does not grant a separate sample license.

`catalog.json` contains stable sample IDs, original source timestamps, precise average BPM, frame/beat counts, waveform envelopes, and detected transient-start frame indices. Bar labels count four pulses, a practical convention for these live polyrhythmic recordings.

The original PCM is not quantized. The app uses whole-loop rate scaling in Tape mode. Slice mode schedules detected attacks at proportionally scaled positions while reading their audio at its original pitch, with short crossfades and decaying tail extension for slower tempos. It retains internal swing. It is not stem separation or a spectral time-stretcher; extreme tempos can expose slice/tail artifacts.

Regenerate metadata/imports with `Scripts/prepare_samples.py <directory-containing-the-two-original-packs>`; dependencies are documented at the top of that script. Regeneration is unnecessary for building or running the app.

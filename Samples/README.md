# Breakwater sample library

222 stereo 48 kHz / 24-bit PCM WAV loops across 13 song pages. The initial 60 Niagara loops retain their original files and IDs (0–59). The October 14 percussion expedition contributes 162 active loops with stable IDs through 299. Retired IDs remain unused: 60–65, 84–101, 120–137, 156–173, 192–203 and 240–245.

These are decoded exports of lossy online streams (YouTube, plus a public Apple Music preview for Swingland Hit), not lossless masters. Audio rights remain with their respective owners; the application source does not grant a separate sample license.

## Original packs

- **Sangandongo** — 30 loops from 12:00–14:00, approximately 105 BPM. [Recording](https://www.youtube.com/watch?v=hTAdzPG4iNQ).
- **Malanga** — 30 loops across the performance, approximately 150 BPM. [Recording](https://www.youtube.com/watch?v=houWewbo9yc).

## Percussion expedition

| Source | Loops | Approx. BPM | Source audio |
|---|---:|---:|---|
| Bumps — A Safe Balm | 18 | 132 | [Recording](https://www.youtube.com/watch?v=JRw1a9_jZR4) |
| Guem & Zaka Percussion — L'abeille | 18 | 115 | [Recording](https://www.youtube.com/watch?v=YvhXCbeQ5Go) |
| Steve Reich & Third Coast Percussion — Music for Pieces of Wood | 18 | 139 | [Recording](https://www.youtube.com/watch?v=DVV_D7EPPB4) |
| Okay Temiz — Penguin | 18 | 89 | [Recording](https://www.youtube.com/watch?v=wRuksYr1J0E) |
| Valentina Magaletti & Julian Sartorius — Sobaka | 18 | 121 | [Recording](https://www.youtube.com/watch?v=3YLmlkUojF8) |
| Bumps — Biotic Discussion | 18 | 126 | [Recording](https://www.youtube.com/watch?v=qdFC1eIBAMs) |
| Bumps — Can You See? | 12 | 158 | [Recording](https://www.youtube.com/watch?v=57klyQWXC1U) |
| Bumps — Sniper Growl | 12 | 128 | [Recording](https://www.youtube.com/watch?v=H-p_NFHIheU) |
| Bumps — Nashira | 12 | 116 | [Recording](https://www.youtube.com/watch?v=p53XYbNu8lg) |
| Bumps — Dawn At Dawn | 12 | 100 | [Recording](https://www.youtube.com/watch?v=xpOnx0LJM8E) |
| Bumps — Swingland Hit | 6 | 102 | [Public preview](https://music.apple.com/us/album/swingland-hit/254274352?i=254275602) |

BPM is measured per cut from its frame length and assigned beat count. Page BPM is the median of that page's loops. Four-pulse bars are a sampling convention for live and polyrhythmic material, not a statement about the original score.

**Library curation:** Locked Groove 022, Le Serpent, Rose Rhythm, Third Construction and Perspective III were removed at the user's request (72 loops). Their Desktop/output packs are archived under `Removed from Library`; web and native bundles omit their audio. `removed-songs.json` records their retired pad IDs.

**L’abeille and Sobaka alignment:** 26 cuts were revised and 10 retained exactly. L’abeille follows the repeating low-drum phrase. Sobaka follows the kick pattern where present and other drums/local pulse where it is absent. Each pack's `pattern-alignment.json` records the reference, exact source frames, fallback anchors and changes. All pad IDs, numbers and bar lengths are preserved; the other 186 active WAVs and catalog entries are unchanged. Revised cuts await listening review.

**Export scope:** future updates maintain the web player, iPad app, stereo WAV dumps and looping audition files. OP-1 exports are no longer maintained at the user's request; existing presets remain as legacy files in the sample dumps.

**Four further Bumps pages:** Sniper Growl, Nashira and Dawn At Dawn each have eight two-bar and four four-bar cuts. Swingland Hit has four two-bar and two four-bar cuts from a public 30-second Apple Music preview; its timestamps are explicitly relative to the preview, whose full-track offset is unknown. New IDs are 258–299; existing active pad IDs are preserved. Kick-led starts share a per-song rhythmic reference. Each new pack’s `curation.json` records source frames and selection checks. The 42 new cuts await listening review.

**Sniper Growl kick-kick-snare starts:** after listening feedback, all 12 cuts were circularly rotated to the later kick pair before the snare. Two-bar cuts move roughly 5½ beats, four-bar cuts roughly 13½, snapped to local attacks. Pitch, frame counts, BPM and pad IDs are unchanged; waveform and slice markers follow the audio. Pad 05 retains an overlapping fill. `Expedition/sn/kick-phrase-alignment.json` records exact offsets and source spans. Web/native WAVs and audition dumps are updated; legacy OP-1 presets are unchanged. The new starts await user audition.

**Snare anchors for Penguin and Biotic Discussion:** use the backbeats on 2 and 4 to establish bar timing, including when kicks anticipate the beat. Penguin 06 is the user-approved reference and remains byte-identical. Twelve Penguin cuts and six further Biotic cuts were realigned; `backbeat-alignment.json` in each pack records source boundaries and snare timing. Internal swing and pitch are untouched. Web audio, offline auditions and OP-1 patches are synchronized; revised cuts await user audition.

**Can You See? phrases:** following listening feedback, this page contains only two- and four-bar loops: eight two-bar cuts (07–14) and four four-bar cuts (15–18). The one-bar cuts (01–06) were removed from the app and sample packs. Pad IDs, numbers, lengths and BPM are preserved. After the user approved pad 07 starting at source 00:09.301, all 12 retained loops were circularly rotated to the corresponding kick-led phrase. Pad 07 preserves the approved preview PCM exactly; the remaining 11 edits await listening review. Waveforms, native transient slices, web/offline auditions and OP-1 patches follow the rotated audio. Source timestamps marked `(wrap)` return to the new first kick after crossing the old segment boundary; `sourceSegments` records the exact two source spans. `selection.json` records the selection, `kick-phase-alignment.json` records the rotations, and `downbeat-alignment.json` preserves the earlier boundary-edit history.

**A Safe Balm downbeats:** after audition feedback, 14 cuts were moved to nearby kick-led bar downbeats using unchanged pads 02 and 05 as references. Pads 07 and 14 also remain unchanged. A subsequent report that 09 felt offset led to replacing it with the next complete two-bar phrase, 00:39.888–00:43.523; every other pad remains byte-identical to the preceding version. Pad IDs, numbers and bar lengths are preserved. `Expedition/sb/downbeat-alignment.json` records the earlier edits, and `pad09-revision.json` records the replacement. The revised pad is ready for listening review.

New cuts follow detected transient entries and score neighboring rhythm/phrase similarity. They keep the recording's original pitch and internal timing, with no quantization, time stretch, EQ or compression. Each track receives only a common gain reduction if needed to keep peaks below -1 dBFS; raised-cosine edge fades are 0.75 ms in / 3 ms out. WAV sampler markers span the whole file.

`catalog.json` includes stable IDs, source timestamps, measured BPM, frame/beat counts, waveform envelopes and transient indices. `Expedition/sources.json` lists source recordings and timing caveats; `Expedition/validation.json` records hashes, PCM lengths, levels and seam checks. All new WAVs pass decode/format/boundary checks. These remain audition candidates except where a specific user-approved reference is noted above.

The native app supports Tape and Slice modes. The browser uses whole-loop pitch/rate scaling and downloads only selected loops, caching them for the visit. Only the trimmed WAVs and catalog ship in the Pages artifact. Source recordings, MP3 reels and OP-1 patches are in the separate sample dumps.

`Scripts/prepare_samples.py` refreshes the original Niagara packs while preserving subsequent catalog entries and IDs. The catalog is already prepared; no Python audio-analysis dependencies are needed to build or run the app.

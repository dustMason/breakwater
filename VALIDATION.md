# Validation

## Can You See? phrase lengths — 2026-10-14

- User listening feedback requires loops of at least two bars. Removed six one-bar cuts (01–06 / catalog IDs 240–245), retaining eight two-bar loops (07–14) and four four-bar loops (15–18). All retained WAVs and OP-1 patches are byte-identical; pad IDs, numbers, and every other song are unchanged.
- All 252 catalog/WAV checks and 13 JavaScript tests pass; the static site builds. The offline player passes JavaScript syntax checks, the regenerated numbered MP3 decodes, and Desktop pack checksums match. Each export contains exactly twelve retained WAVs and native OP-1 patches.
- Browser verification shows only pads 07–18, labeled two or four bars. The refreshed player is stopped on Can You See? at 158 BPM. No audio was played during this check.

## Penguin and Biotic snare anchors — 2026-10-14

- Followed the user's instruction to anchor snare backbeats on 2 and 4. Penguin 06 is the explicit reference and stays byte-identical in WAV and OP-1 form. Twelve Penguin cuts and six further Biotic cuts have updated boundaries. Each pack's `backbeat-alignment.json` supersedes kick-only phase selection and records detected backbeats, boundary edits and timing errors.
- Snare intervals were tracked through each relevant source region; one absent Biotic backbeat was interpolated from its neighbors and is recorded in the working grid. Boundary timing was fitted locally to the backbeats while retaining each reference's phase offset. Existing cuts within 50 ms of that phase were retained. Only boundaries changed: no internal quantization, pitch change or time stretching. Measured backbeat timing errors stay below 43 ms in Penguin and 37 ms in Biotic, including retained cuts and natural performance variation.
- All 258 catalog/WAV checks pass. All 36 OP-1 patches pass official-codec re-import and independent mono PCM, length and boundary checks. Unchanged patches and WAVs are byte-identical; the other twelve songs and all pad IDs are unchanged. The static site builds successfully. Revised cuts still need user audition and physical OP-1 playback.
- Both offline players pass JavaScript syntax checks and both numbered MP3 reels decode. Desktop pack checksums match the revised exports. Muted browser playback of Penguin 01 and Biotic Discussion 05 was verified; the player is stopped on Penguin at 89 BPM with volume restored.

## Remaining Bumps downbeat revisions — 2026-10-14

- Recut 15 Biotic Discussion pads and 13 Can You See? pads after the user reported wrong-beat starts. Source bar phase and low-frequency attacks guided nearby kick-led entries. IDs, pad numbers and 1/2/4-bar lengths remain stable; pitch and internal timing are unchanged. Per-pack `downbeat-alignment.json` records exact source-frame edits and distinguishes analysis-selected references from user-approved ones.
- Biotic Discussion 01/02/05 and Can You See? 01/05/06/09/13 retain byte-identical WAVs and OP-1 patches. All other songs, including the preceding A Safe Balm correction, are unchanged.
- All 258 catalog/WAV checks pass. The 36 OP-1 patches pass official-codec re-import and independent mono PCM, length and boundary checks. The regenerated offline players pass JavaScript syntax checks; numbered MP3 reels decode. Both updated Desktop packs are checksum-verified against the outputs.
- Static build succeeds. Muted browser playback of revised Biotic Discussion 04 and Can You See? 02 was verified; the player is stopped on Can You See? at 158 BPM. These digital checks do not replace a listening review or physical OP-1 playback.

## A Safe Balm downbeat revision — 2026-10-14

- User identified pads 02 and 05 as preferred kick-led downbeats and 01 as a snare entry. Recut 14 pads from nearby source bar downbeats, retaining pad IDs, numbers and 1/2/4-bar lengths. WAVs and OP-1 patches for 02, 05, 07 and 14 are byte-identical to the previous version. Other songs are unchanged.
- `Samples/Expedition/sb/downbeat-alignment.json` records source-frame edits and the reference phase. Low-frequency onset checks distinguish the selected kicks from the rejected snare entries. Internal timing and pitch remain untouched; the revised cuts await the user's listening review.
- All 258 catalog/WAV checks pass. All 18 revised-pack OP-1 presets pass official-codec re-import and independent mono PCM/length/boundary checks. The static build succeeds, and muted browser playback of revised pad 01 was verified. The refreshed player is stopped on A Safe Balm at 132 BPM.
- Regenerated offline looping player, numbered MP3, WAVs, indices and OP-1 patches; the Desktop A Safe Balm pack was checksum-verified against the output. Physical OP-1 playback remains untested.

## Percussion sample expansion — 2026-10-14

- Added 198 loops from all twelve retained playlist recordings: ten sources × 18, Third Construction × 12, Locked Groove 022 × 6. Total catalog: 14 songs / 258 loops. Original Niagara entries and IDs are unchanged.
- Every new 48 kHz / 24-bit stereo WAV decoded successfully; PCM lengths, BPM/beat consistency, finite samples, peaks ≤ −1 dBFS, zero seam endpoints and sampler markers were checked. Representative seam plots were visually inspected. Source URLs, exact times, timing interpretations and per-file hashes are recorded in the sample catalog/provenance.
- 198 original OP-1 drum presets were produced with the official utility codec, using one isolated codec process per source pack. Every output re-imported as mono with Loop mode, pitch zero, correct key mapping and endpoints within three frames. An independent PCM check verified 44.1 kHz / 16-bit, <12 seconds, zero boundaries and bit-identical audio to the prepared mono conversion. Physical OP-1 import/playback remains untested.
- All twelve numbered MP3 reels decode; all twelve embedded-audio offline players pass JavaScript syntax checks. The 496-file Desktop sample-dump copy was checksum-verified against the prepared output.
- `npm test`: 13 tests pass, including overlapping on-demand loads, no unrelated downloads, failed-load retry and exclusions changing during decoding. `Tests/ClockAndCatalogTests.py` passes for all 258 WAVs. Static build succeeds and all 267 required assets return HTTP 200. Complete site is approximately 293 MB; Pages deployment has not run.
- Browser checks at the existing desktop viewport: all fourteen songs in the dropdown; muted playback from each new song; Shift-click next-bar cycles; source-tempo reset; cross-page browsing without interruption; new-ID exclusions persisting through reload and restored after testing; reload does not autoplay. Inspected console has no warnings/errors. The layout/CSS is unchanged; the new library has not been physically tested on iPad.
- These are algorithmically selected audition candidates, with no human listening pass. Third Construction's bar/tempo labels are practical editing interpretations, and Locked Groove 022's six files are length/phase variants of its repeated 1.8-second cycle.

## Static browser player — 2026-10-14

- `npm test`: 11 JavaScript tests passed. Covers next-bar replacements, complete 1/2/4-bar cycles, cross-song selection, smooth tempo changes, measured pitch scaling, disabled-pad removal/fade-out, cancellation of excluded pending pads, stop/restart, transition discontinuities, gesture ordering, and all 60 catalog records.
- `node --check` passed for the page/controller/AudioWorklet modules.
- `python3 Scripts/build_web.py` assembled the site. A local `/breakwater/` deployment layout served all 69 required assets (HTML, JavaScript, CSS, icon, catalog and 60 WAVs) with successful responses and JavaScript MIME types. The artifact excludes native source, repository metadata and development documents. Pages workflow YAML parsed; deployment depends on the tested build.
- Browser UI checks exercised initial loading/decoding of all 60 samples into the AudioWorklet, playback, next-bar selection, Shift-click cycles, tempo entry, source tempo, switching song pages without stopping playback, and exclusions surviving reload. Both root and `/breakwater/` paths worked. Preview volume was zero; this was not an audible listening test. Browser error/warning logs were empty in the inspected session.
- Dark-appearance screenshots inspected at 1440×900, 820×1180 and 390×844. Desktop/tablet grids and bottom transport fit; the narrow phone layout intentionally scrolls the grid while retaining transport. No horizontal overflow in the measured phone viewport. Small-screen touch behavior uses vertical pan and release-to-launch; physical multi-touch/scrolling remains unverified.
- GitHub Pages deployment has **not** run. User will create/push and enable the GitHub Actions Pages source. Physical A12 iPad Safari, browser interruption/background behavior, light-appearance screenshots and audible quality still need hands-on validation.

Validation date: 2026-10-14. Xcode 27.0 (27A266a), iPadOS deployment target 17.0.

## Automated audio and data checks

`Scripts/test_core.sh` passes with AddressSanitizer and UndefinedBehaviorSanitizer enabled. It covers next-bar replacement, full-length cycling, exclusion changes during playback and pending queues, smooth tempo steps, MIDI Start/Stop/Continue and Song Position Pointer, jittered MIDI clock over 80 bars with a 120→145 BPM change, clock dropout and a missing first clock, stop fades, and the distinction between rate-shifted and original-pitch sliced audio.

The clock simulation keeps phase error below 0.09 beats under the tested ±0.6 ms jitter pattern. This is a software simulation, not a measured USB/audio round-trip result. A 440 Hz test signal at 75% tempo measures approximately 330 Hz in Tape and 442.5 Hz in Slice; the short-window crossing estimate and splice boundaries explain the Slice estimate's tolerance.

`Scripts/test_interactions.sh` passes. It covers ordered multi-touch gesture state, release latching, fresh-gesture replacement, MIDI running status and interleaved realtime messages. All 60 bundled WAVs pass format, stable ID, frame count, beat length, waveform and slice-boundary checks.

## Native build and interface

- Debug build succeeds for iPad Simulator.
- Release build succeeds for generic physical iPad (arm64), with signing disabled.
- Four XCUITests pass on the iPad (A16) Simulator running iOS 27: launch/queue/song switching/Tape-Slice, persistent exclusions and restoration across relaunch, drag cycle/portrait/settings, and control reachability.
- The appearance test also passes in dark mode with Accessibility Extra Large text. Native captures cover landscape, portrait, settings and dark large text.
- Layout uses real waveform data. Blue playback sweeps and queue state are driven by the running audio engine.

## Still requires the actual iPad

The A12 iPad, CME adapter, simultaneous physical fingers, output latency, long-session thermal performance, cable reconnection, interruptions and audible Slice quality over the user's preferred tempo range have not been tested on hardware. Simulator and synthetic tests do not establish those results. Minimum iPadOS 17 compatibility is compiled, not exercised on an iPadOS 17 runtime.

On first device run, connect a wired output to the mixer, enable Follow MIDI clock, select the adapter, and send Start from the master. Check tempo changes and Stop/Continue, build a cycle with several fingers, and adjust Timing offset by ear. App signing requires the user's personal Apple development team in Xcode; GitHub identity does not provide iPad signing.

## Design verification

The user approved mockup C with a song dropdown replacing the tabs. The implementation keeps the bottom transport dock, dominant waveform grid, source tempo, blue active state and queued order. It adapts to native safe areas, real sample data, light/dark appearance and Dynamic Type.

The Impeccable browser-oriented build-phase pipeline remains at its extra plan/asset approval checkpoint. There are no painted assets in the grid; all regions are native controls or PCM waveform geometry. No browser receipt was fabricated and no duplicate approval was requested after the user's explicit approval of C. The native Simulator review is the applicable evidence; see DESIGN.md for the finished system and review record. The native finish reviewer scored both requested fixes resolved: secondary labels now measure 6.69:1 on white, and MIDI cable guidance names the master’s MIDI OUT port. The final disposition is ship at the scope of those fixes. Screenshots are in Docs/Design.

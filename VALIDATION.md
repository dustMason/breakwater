# Validation

## Sniper Growl last kick and Swingland Hit second kick, build 5 — 2026-10-14

- Following further listening feedback, all 12 Sniper Growl cuts now begin on the last kick of their preceding version, roughly one beat earlier in circular order. This supersedes the prior kick-kick-snare starting phase. All six Swingland Hit cuts now begin on the second close opening kick; the chosen transient is about 0.12–0.15 seconds after the original start. Preview-relative timestamps remain explicit. Both sets await user audition.
- Circular rotations preserve exact lengths, BPM, beat counts, pad IDs and pitch. PCM is unchanged apart from rotation and 0.75 ms / 3 ms edge fades. Source spans correctly compose across Sniper Growl’s previous wrap; waveforms and slice markers follow the PCM. All 204 other WAVs are unchanged. Reports retain the earlier phase history.
- All 222 catalog/WAV checks and 13 web tests pass. Static, Debug Simulator and unsigned Release device builds pass; all three catalogs and all WAV hashes match the canonical library. No playback/UI code changed and native UI tests were not repeated for this audio revision. Physical iPad playback remains unverified.
- Both offline players embed the exact exported WAVs and pass JavaScript syntax checks; both numbered MP3 reels decode. Desktop packs are checksum-verified, with prior versions retained in Revision Backups. OP-1 files were not regenerated and retain their older starting phase.
- Browser reload shows Sniper Growl's new timestamps and waveforms without autoplay. The page was left stopped for audition; the inspected console contains no warnings/errors. Digital checks do not establish listening approval.

## Sniper Growl kick-kick-snare phase, build 4 — 2026-10-14

- Rotated all 12 existing cuts to the later kick pair before the snare, following the user's description. Two-bar cuts shift about 5.5 beats; four-bar cuts use the corresponding phase about 13.5 beats in. Local transient snapping follows the performance rather than a rigid beat grid. Pad 05 retains an overlapping fill. The new starts await listening feedback.
- Exact frame counts, BPM, beat counts and pad IDs are preserved. PCM is unchanged except for circular rotation and 0.75 ms / 3 ms edge fades. Waveforms, transient markers, wrapped source spans and quality hashes follow the audio. All 210 other WAVs and catalog entries are unchanged.
- All 222 catalog/WAV checks and 13 web tests pass. Static, Debug Simulator and unsigned Release device builds pass; all three catalogs and every WAV match the canonical library. No playback/UI code changed. Native UI tests were not repeated for this audio-only revision; physical iPad playback remains unverified.
- The offline player's embedded WAVs match the exported files, its JavaScript passes syntax checks, and the regenerated numbered MP3 decodes. The Desktop pack is checksum-verified and its prior version backed up. OP-1 presets were left unchanged, per the user's request to discontinue those exports.
- Browser reload shows the revised timestamps/waveforms. Pads 01 and 02 were observed playing while the user auditioned; no warnings/errors appeared in the inspected console. Ongoing user playback was left alone. This observation does not establish listening approval.

## Curated library, build 3 — 2026-10-14

- Final library: 13 song pages / 222 stereo WAVs. Added 42 Bumps cuts: Sniper Growl, Nashira and Dawn At Dawn have 12 each; Swingland Hit has six from its public 30-second Apple Music preview, with preview-relative timestamps. Removed Locked Groove 022, Le Serpent, Rose Rhythm, Third Construction and Perspective III (72 cuts). Removed pad IDs remain retired. Desktop/output packs are archived under `Removed from Library`.
- Revised 12 L’abeille cuts and 14 Sobaka cuts using recurring low-drum patterns; Sobaka uses other drums/local pulse where a clear kick is absent. Ten cuts on those two pages remain byte-identical. The other 186 active WAVs and catalog entries are unchanged from the post-addition baseline. Reports record exact source frames and analysis-selected references; the revised cuts await user audition.
- All 222 catalog/WAV checks and all 13 JavaScript tests pass. The static site builds; its catalog and every WAV match the canonical samples, with no retired WAVs left behind. The static builder now removes samples listed in the previous output catalog that are absent from the current catalog.
- Muted browser playback verified revised L’abeille 01 and Sobaka 07. After the final removal, browser reload shows all 13 retained songs and none of the five removed pages, with no autoplay. The player is stopped on L’abeille at 115 BPM with volume restored. The four new Bumps pages were also exercised during the addition step. No warning/error messages appeared in the inspected browser console.
- New and revised WAV dumps, embedded-audio offline players, numbered MP3 reels and indices were checked and synchronized to Desktop with checksum verification. OP-1 maintenance was discontinued at the user's request after the exports already generated during this work; existing presets remain legacy files. No further OP-1 export is part of the update workflow.
- Debug Simulator and unsigned Release device builds pass. Both bundles have the exact 13-page catalog and all 222 canonical WAVs, with retired audio absent. The focused library playback test passes across ten retained/revised/new pages, alternating Tape and Slice. A playback-mode UI assertion intermittently timed out when tapping the segmented control during playback. The focused library check now selects Tape/Slice while stopped, alternates the modes across song pages, then verifies each pad reaches Playing and stops. Audio remained muted throughout Simulator checks. The initial in-playback assertion failure is not evidence that live Tape/Slice switching has been fixed; application playback code was unchanged. Physical iPad performance, signing and installation remain unverified.

## Native library refresh, build 2 — 2026-10-14

- Rebuilt the iPad app with the shared current catalog: 14 songs and 252 loops. Both the Debug Simulator bundle and Release arm64 device bundle have byte-identical catalogs and WAV hashes to `Samples/`; all six retired Can You See? WAVs are absent. This includes the latest Safe Balm 09 replacement and Penguin/Biotic backbeat edits.
- MIDI notes now follow displayed pad numbers after curation: Can You See? 07 remains note 42 and 18 remains note 53; removed pads 01–06 stay unmapped. Swift interaction/MIDI tests and all 252 catalog/WAV checks pass. Build number is 2 in both Xcode configurations and the project generator.
- Native UI checks pass for launch/queue/song switching, drag cycles/portrait/settings, appearance, and all four revised song pages. The expanded-library test loads and plays Safe Balm 09, Penguin 06, Biotic 01, and Can You See? 18; it checks Tape/Slice selection and the absence of retired pads. The saved-exclusions test initially tapped before loading finished on relaunch; after adding the same readiness wait used at initial launch, its focused rerun passes. Test audio is muted using a Debug-only launch option.
- Release device build succeeds with signing disabled. The verified Debug build is installed in the existing iPad (A16) Simulator. No physical iPad was detected; signing, installation, MIDI hardware timing and A12 performance remain to be checked on the user's device.

## A Safe Balm pad 09 replacement — 2026-10-14

- After the user reported an offset in 09, compared its local rhythm with approved pads 02/05. The opening includes an extra early snare and an ambiguous kick entry. Replaced it with the next full two-bar phrase, 00:39.888–00:43.523 (132.056 BPM), retaining its ID and number. This is a neighboring phrase replacement, not an internal timing adjustment; the revised cut awaits user audition.
- All other 17 WAVs and OP-1 patches are byte-identical, and all other catalog pages are unchanged. All 252 catalog/WAV checks pass. The 18 OP-1 patches re-import through the official codec and pass independent PCM/format/length checks. The offline player's JavaScript and numbered MP3 validate; the Desktop pack is checksum-verified.
- Static build passes. Muted browser playback loaded the new 09 and showed it playing with the revised timestamps. The player is stopped on A Safe Balm at 132 BPM with volume restored. Physical OP-1 playback remains untested.

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

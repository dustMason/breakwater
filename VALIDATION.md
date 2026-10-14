# Validation

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

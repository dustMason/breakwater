# Breakwater
<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack
Native iPad app: SwiftUI and UIKit for multi-touch performance controls; AVAudioEngine and Core MIDI; a shared Rust real-time audio engine. iPadOS 17+, targeting an A12 iPad. Xcode project, no runtime package dependencies.

Browser adaptation: static HTML, CSS and JavaScript with Web Audio and an AudioWorklet hosting the same engine as WebAssembly. Both platforms fetch the same separately hosted sample catalog and audio. No application server or runtime package dependencies; browser audio requires HTTPS or localhost and a user gesture to start.

## Users
Jordan, playing a live synth jam with an external MIDI clock source and a CME U2MIDI Pro connected through Apple's camera adapter on iPad, or choosing songs and playing loops with an internal tempo in a browser.

## Product Purpose
Play the selected percussion loops continuously, at the jam's tempo, with fast musical selection and no gaps between phrases.

## Capabilities and Constraints
- A scrollable library groups 222 loops into 13 song folders: Sangandongo and Malanga (30 each), six expedition tracks (18 each), Can You See? (12 two- and four-bar loops), Sniper Growl/Nashira/Dawn At Dawn (12 each), and Swingland Hit (six from a public preview).
- The two stacks show stylized waveforms, a blue playing state and a moving playhead. Each clip has independent part switches, a low-pass/high-pass filter knob and a vertical level fader.
- Activate a loop to add it to the quieter crossfader side, or drag it onto A or B. The less-populated side wins a centered tie, with A first. Up to eight clips per side loop concurrently, including across songs. New clips start with all four parts on; additions and removals take effect at a bar boundary without restarting retained clips.
- Loops repeat indefinitely; disabled pads persist across launches and cannot enter either stack. Browser persistence uses local storage, with visit-only exclusions if storage is unavailable.
- Native iPad: tape-style rate/pitch change or transient-sliced playback at original pitch; external MIDI clock and transport, smooth tempo changes, and internal tempo for standalone use.
- Browser: tape-style rate/pitch change only, with editable BPM, tap tempo, source-tempo reset and volume. No MIDI or original-pitch slicing. Mouse or touch drag targets a stack; Alt+Left/Right are keyboard alternatives. Song browsing preserves playback.
- Show approximate source-song BPM with a transport along the bottom. Show A and B side by side, keep the crossfader and transport visible, and preserve touch-sized clip controls with scrolling for crowded stacks.
- Keep sample audio outside the code repository; provenance and publishing scope are documented separately.
- Prepare static browser output for GitHub Pages on the user's personal repository.
- Exact iPad model/iPadOS version and physical MIDI/audio routing remain unverified.

## Evidence on Hand
222 trimmed stereo PCM WAV loops with source-time/beat-count indices. The eleven active expedition packs also have offline looping auditions, numbered MP3 reels, and legacy original OP-1 loop patches (no longer maintained). Browser playback loads selected clips on demand. Existing standalone audition UI provides a visual baseline: dense grids, clear waveforms, blue active states, thin rules, minimal chrome.

The browser adaptation retains the native design identity. `.impeccable/surfaces/web-index-html.md` records its platform-specific adaptations; `.impeccable/review/web-finish-review.md` records the scoped visual ship disposition. `VALIDATION.md` owns functional and hardware evidence; browser captures do not establish physical touch performance or publication.

## Product Principles
Performance controls stay large and direct. Sound continues while pages and settings change. New clips launch on musical boundaries. Native hardware sync state is visible. Audio work never blocks on UI or disk access.

# Breakwater
<!-- impeccable:product-schema 1 -->

## Platform

ios, web

## Stack
Native iPad app, as agreed in the discussion: SwiftUI and UIKit for multi-touch performance controls; AVAudioEngine and Core MIDI; a portable C++ real-time audio engine. iPadOS 17+, targeting an A12 iPad. Xcode project, no runtime package dependencies.

Browser adaptation: static HTML, CSS and JavaScript with Web Audio and an AudioWorklet. The same committed sample library supplies both platforms. No server or runtime package dependencies; browser audio requires HTTPS or localhost and a user gesture to start.

## Users
Jordan, playing a live synth jam with an external MIDI clock source and a CME U2MIDI Pro connected through Apple's camera adapter on iPad, or choosing songs and playing loops with an internal tempo in a browser.

## Product Purpose
Play the previously chopped Niagara drum loops continuously, at the jam's tempo, with fast musical selection and no gaps between phrases.

## Capabilities and Constraints
- A scalable song dropdown selects a full-screen grid page per source song. Initially Sangandongo and Malanga, 30 samples each.
- Every pad shows a simple waveform; active playback is visually expressive; queued pads flash.
- Tap queues a loop for the next bar. Multi-touch builds an ordered cycle that stays latched until replaced by another interaction.
- Loops repeat indefinitely; disabled pads persist across launches and cannot enter playback queues. Browser persistence uses local storage, with visit-only exclusions if storage is unavailable.
- Native iPad: tape-style rate/pitch change or transient-sliced playback at original pitch; external MIDI clock and transport, smooth tempo changes, and internal tempo for standalone use.
- Browser: tape-style rate/pitch change only, with editable BPM, tap tempo, source-tempo reset and volume. No MIDI or original-pitch slicing. Mouse drag and Shift-click extend the pad cycle interaction; song browsing preserves playback.
- Show approximate source-song BPM while maximizing grid area. Approved visual mockup C: transport along the bottom, with song tabs replaced by a dropdown.
- Commit the actual sample WAVs in a new private repository under dustMason.
- Prepare static browser output for GitHub Pages on the user's personal repository; repository creation, push and publication remain user steps.
- Exact iPad model/iPadOS version and physical MIDI/audio routing remain unverified.

## Evidence on Hand
60 existing trimmed stereo PCM WAV loops and source-time/beat-count indices in this chat's outputs. Existing standalone audition UI provides a visual baseline: dense grids, clear waveforms, blue active states, thin rules, minimal chrome.

The browser adaptation retains the native design identity. `.impeccable/surfaces/web-index-html.md` records its platform-specific adaptations; `.impeccable/review/web-finish-review.md` records the scoped visual ship disposition. `VALIDATION.md` owns functional and hardware evidence; browser captures do not establish physical touch performance or publication.

## Product Principles
Performance controls stay large and direct. Sound continues while pages and settings change. Queues launch on musical boundaries. Native hardware sync state is visible. Audio work never blocks on UI or disk access.

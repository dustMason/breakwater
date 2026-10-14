# Breakwater
<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack
Native iPad app, as agreed in the discussion: SwiftUI and UIKit for multi-touch performance controls; AVAudioEngine and Core MIDI; a portable C++ real-time audio engine. iPadOS 17+, targeting an A12 iPad. Xcode project, no runtime package dependencies.

## Users
Jordan, playing a live synth jam with an external MIDI clock source and a CME U2MIDI Pro connected through Apple's camera adapter.

## Product Purpose
Play the previously chopped Niagara drum loops continuously, at the jam's tempo, with fast musical selection and no gaps between phrases.

## Capabilities and Constraints
- A scalable song dropdown selects a full-screen grid page per source song. Initially Sangandongo and Malanga, 30 samples each.
- Every pad shows a simple waveform; active playback is visually expressive; queued pads flash.
- Tap queues a loop for the next bar. Multi-touch builds an ordered cycle that stays latched until replaced by another interaction.
- Loops repeat indefinitely; disabled pads persist across launches and cannot enter playback queues.
- Tape-style rate/pitch change or transient-sliced playback at original pitch.
- Follow external MIDI clock and transport, handle tempo changes smoothly, and provide internal tempo for standalone use.
- Show approximate source-song BPM while maximizing grid area. Approved visual mockup C: transport along the bottom, with song tabs replaced by a dropdown.
- Commit the actual sample WAVs in a new private repository under dustMason.
- Exact iPad model/iPadOS version and physical MIDI/audio routing remain unverified.

## Evidence on Hand
60 existing trimmed stereo PCM WAV loops and source-time/beat-count indices in this chat's outputs. Existing standalone audition UI provides a visual baseline: dense grids, clear waveforms, blue active states, thin rules, minimal chrome.

## Product Principles
Performance controls stay large and direct. Sound continues while pages and settings change. Queues launch on musical boundaries. Hardware sync state is visible. Audio work never blocks on UI or disk access.

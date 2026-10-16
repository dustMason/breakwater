# Breakwater

A native iPad instrument and a static browser player for percussion loops. The native app supports MIDI-synchronized synth jams on iPadOS 17+, designed for an A12 iPad. The sample library has 222 loops in 13 song folders: the original 60 Niagara cuts plus 162 loops from the percussion audition shortlist. See [the sample catalog](Samples/README.md) for sources and counts.

## Performance behavior

- Browse the scrollable **Library** on the left; expand a song folder to reveal its loops. Opening another folder leaves the sequence playing, and the timeline can combine loops from any folder.
- **Use source** sets the internal tempo to the active folder’s approximate BPM. It is disabled while following MIDI clock, because the external device controls the tempo.
- Drag a loop into the **Timeline**: drop it beneath an existing clip to layer it, or at a step edge or plus target to insert a step before, after, or between other steps. Tapping a library loop adds it to the end; the iPad library’s **Add** menu can change the tap action to insert before or after the selected step or add a layer. The sequence repeats; each step lasts as long as its longest loop, and shorter layers repeat underneath. The timeline fits the sequence when space allows and scrolls horizontally when the clips need more room; use the zoom controls to inspect it more closely and **Fit** to return. Changes during playback take effect at a four-beat bar boundary. Editing a different step preserves the current phrase; changing the playing step's layers re-cues that step together at the boundary.
- Each timeline clip, including separate copies of the same loop, has its own part switches, filter knob and vertical level fader. Tap a clip's waveform to select it for placement; adjust its controls directly. Remove clips with their × controls, or use **Clear**. An arrangement can contain up to 64 clips, with at most eight in one step. Arrangement and clip settings last for the current session; loop exclusions remain persistent.
- Use **Nudge** in the bottom bar to move the playing loop earlier or later in 10 ms steps; hold either arrow to repeat. The adjustment settles smoothly and follows queued loops. When following MIDI clock, it changes the alignment against the master without changing its tempo or the saved latency setting. Switching clock modes clears the MIDI nudge adjustment.
- **Edit** in the library toggles persistent exclusions. Disabled loops remain visible so they can be restored. They cannot be launched by touch or MIDI and are removed from cycles. Disabling a playing loop changes the arrangement on a bar boundary; if none remains, playback fades out.
- **Tape** follows tempo by changing playback rate and pitch together.
- **Slice** schedules precomputed drum transients against the beat clock, plays their attacks at original pitch, and uses short crossfades / decaying tail extension. It preserves the original internal swing, rather than quantizing every hit to a rigid subdivision. Extreme tempo changes can reveal slicing artifacts.
- Each clip's filter knob is bypassed at the center: drag down for low-pass or up for high-pass, and double-tap or double-click to reset. The master filter in the bottom bar affects the overall output and offers Off, low-pass, band-pass and high-pass with a smoothed cutoff.
- Each clip offers four DrumSep estimates: **Kick, Snare, Toms and Cymbals** (including hi-hats). Use **All off** and bring them in one by one, or switch individual parts while playing. Its stylized waveform highlights the enabled parts against a faint preview of the original. Separation can contain bleed or artifacts; hand percussion may be assigned to the nearest kit category. The unmodified original plays when all four parts are on.

## MIDI and audio

Connect the clock source's MIDI OUT to the CME U2MIDI Pro's white **TO MIDI OUT** plug; connect its USB end to the iPad through Apple's USB camera adapter. Audio goes separately from the iPad's headphone output or an audio interface to your mixer.

Select the MIDI source and enable external clock in Settings. Incoming MIDI Clock, Start, Stop, Continue and Song Position Pointer are supported. Start establishes bar one; Align downbeat can establish it when joining a running jam. Note numbers 36–65 trigger loops 01–30 in the active song folder; removed loop numbers remain unmapped (Can You See? starts with loop 07 at note 42). Held notes form a sequence that remains after release. Notes are accepted on all channels.

Clock smoothing and a phase correction loop reject small timing jitter without jumping the sample cursor. Tempo changes slew over roughly 90 ms, in addition to the short incoming-clock measurement window. If clock vanishes, playback briefly freewheels; after two seconds it fades out and waits for transport restart. The latency offset advances playback for positive values. Physical timing should be calibrated against the actual audio output.

The app requests a 256-frame audio buffer at 48 kHz; iPadOS chooses the available hardware configuration. Loops and separated parts download and decode off the audio thread when selected. Current playback continues while a replacement loads, and its first launch occurs on a bar boundary after loading. The iPad caches downloaded audio on disk for offline use; files not yet cached require a connection. While a playing loop's parts are preparing, its full mix continues unless all parts are off, in which case it fades to silence. Rendering uses owned in-memory PCM and a bounded single-producer command ring; the render callback performs no file I/O, locks, allocation, or Swift UI work. Audio can continue in the background. Audio interruptions stop playback; a disconnected output requires a deliberate restart.

The shared mixer scales a stack of N full-level clips by 1/√N. The scaling follows clip levels and all-parts-off mutes smoothly, so zero-level or fully muted clips do not consume headroom; changing one clip's level can also change the gain of the other layers. A gentle stereo-linked compressor (2:1 above approximately −2.5 dBFS, 2 ms attack, 150 ms release) and a soft sample-peak protector follow the master filter, with no makeup gain. The protector has no lookahead and is not a true-peak limiter; especially dense or strongly correlated layers can still sound compressed or distorted. The same processing is used in the browser and on iPad, before their existing platform output trims.

## Browser player

Install Rust with the `wasm32-unknown-unknown` target, then run locally with Python 3; no npm install or bundler is required:

```sh
rustup target add wasm32-unknown-unknown
source .asset.env # or export BREAKWATER_ASSET_BASE_URL yourself
python3 Scripts/serve_web.py
# Open http://127.0.0.1:8765/
```

The browser version uses the same library folders, timeline, clip settings, next-bar changes, timing nudges, and persistent exclusions. On touch screens, hold a loop briefly before dragging; a quick vertical gesture scrolls the library. Keyboard users can navigate visible loops with the arrow keys and activate with Enter/Space to add a step; Alt+Enter adds a layer to the selected step, and Alt+Left/Right inserts before or after it. On small screens the library scrolls vertically and the bottom transport stays visible.

Enter a tempo, use **Tap tempo**, or **Use source**. Pitch follows speed, with smoothly changing tempo and short transition fades. There is no MIDI or Slice mode in this version. Only selected loops download and decode when first triggered; subsequent plays use the in-memory cache. Rapid selections share in-flight downloads, and failed clips can be retried without reloading successful clips. Playback then runs in an AudioWorklet on the audio thread, independently of animation and main-thread timers. Browser interruptions require pressing Play again. Preferences belong to this browser and are separate from the native app.

Use a current browser with AudioWorklet support. HTTPS or localhost is required; opening `index.html` as a local file does not work. Mobile browsers can suspend audio in the background or when the device locks. Physical iPad/browser background behavior remains unverified.

### GitHub Pages

1. Create/push this repository under your personal GitHub account, with `main` as the branch.
2. In **Settings → Secrets and variables → Actions → Variables**, set `BREAKWATER_ASSET_BASE_URL` to the HTTPS asset-library base URL.
3. In **Settings → Pages → Build and deployment → Source**, choose **GitHub Actions**.
4. Push to `main`, or run **Deploy web player to GitHub Pages** in the Actions tab after enabling Pages.

The workflow tests the shared Rust engine and its WebAssembly host, builds `build/web`, uploads only the static site, and deploys it. For `dustMason/breakwater`, the expected address is `https://dustmason.github.io/breakwater/`. Modules and icons use relative paths; the separate asset URL is inserted into the generated site from the repository variable. No AWS credentials are needed to build or deploy Pages.

Each clip in the timeline has its own level control, from silence to its original level. Copies of the same loop can be adjusted independently, including while they are playing. Level settings stay with the clips while editing the current arrangement; the stacking headroom described above still applies.

**Publishing scope:** the S3 catalog and audio objects are publicly readable; their URL is visible to anyone using the app or site, even though it is not committed here. The dedicated bucket does not permit anonymous listing or writes. The source and derivatives remain subject to the sample provenance described below.

To build for another static host:

```sh
source .asset.env # or export BREAKWATER_ASSET_BASE_URL
python3 Scripts/build_web.py --output build/web
npm test
```

Serve the contents of `build/web` with JavaScript module and WebAssembly MIME types. The web source is in `Web/`; audio is fetched from the configured library rather than copied into the site. For a self-contained local development preview when the original local WAVs and parts are available, run `python3 Scripts/build_web.py --local-assets`.

### Publishing the sample library

The catalog source and preparation scripts live in the repository; WAV and M4A audio files do not. Keep the working audio library in `Samples/` locally, or restore the exact files for the current catalog from the published library with `python3 Scripts/fetch_assets.py` after setting `BREAKWATER_ASSET_BASE_URL`. Restoration verifies hashes and never overwrites different local files. Set `BREAKWATER_ASSET_BUCKET`, `BREAKWATER_AWS_ACCOUNT_ID`, `BREAKWATER_AWS_REGION`, and `BREAKWATER_ASSET_BASE_URL` in an ignored `.asset.env` file or your shell environment. The AWS account ID is checked against the active credentials before publication. Do not store credentials in this file or in Git.

```sh
source .asset.env
python3 -m venv .venv
.venv/bin/pip install boto3
# Authenticate to the personal AWS account using your normal credential provider.
.venv/bin/python Scripts/publish_assets.py
python3 Scripts/configure_assets.py
```

The publisher hashes each audio file, uploads only new immutable objects, and publishes the catalog after all uploads succeed. Old objects are intentionally retained so older clients and cached catalogs continue to work; unused old objects continue to incur storage charges until manually cleaned up. `Scripts/provision_assets.py` can create a new dedicated bucket when needed; it refuses to reconfigure an existing one and does not support creating buckets in `us-east-1`. If using 1Password CLI, inject the standard AWS environment variables with `op run --env-file /path/to/private-aws.env -- .venv/bin/python Scripts/publish_assets.py`; keep that file outside the repository and use 1Password secret references rather than literal credentials. The generated `App/Config.local.xcconfig` and `.asset.env` are ignored by Git. A fresh clone can build the app and site without local audio once the asset URL is configured.

Decoded original loops remain in memory for the current session, so visiting very large numbers of loops can still increase memory use. Restarting the player releases them; bounded in-memory loop eviction is future work.

## Build

See [INSTALL.md](INSTALL.md) for the first physical iPad run and MIDI hookup.

Install Rust and its iOS targets as shown in [INSTALL.md](INSTALL.md), then open `Breakwater.xcodeproj` in Xcode. Select the **Breakwater** scheme, choose your personal Apple development team under Signing & Capabilities, and select the iPad or an iPad Simulator. Xcode builds the dependency-free Rust audio library before linking the app. Apple signing is separate from the GitHub commit identity.

The committed Xcode project can be regenerated with `python3 Scripts/generate_project.py`. Python audio-analysis dependencies and local WAVs are not required to build the app. To regenerate parts after changing loops, follow [DrumSep preparation](Docs/DrumSep.md): install the isolated offline dependencies and original checkpoint, then run `Scripts/separate_parts.py`. The model runs only during sample preparation; the app loads the generated audio.

## Checks

```sh
Scripts/test_core.sh
Scripts/test_differential.sh
Scripts/test_interactions.sh
```

The first runs Rust ownership/concurrency and output-dynamics tests, and tests bar-boundary changes, layered steps, exclusions, clock jitter, tempo steps, phase lock, clock loss, MIDI transport, pitch behavior, per-clip muting and filters. The differential test compares transport throughout and settled single-layer audio against the former C++ engine at 44.1 and 48 kHz; stacked audio intentionally differs because the old mixer used averaging. Its C++ reference and harness are instrumented with AddressSanitizer and UndefinedBehaviorSanitizer, but the linked Rust library is not. The interaction test checks MIDI parsing, catalog metadata, and the native online/offline cache; it also verifies sample formats when local files are present. `npm test` tests the actual WebAssembly module, layer mixing, and worklet loading protocol. `python3 Tests/AssetPublisherTests.py` and `python3 Tests/AssetRecoveryTests.py` test publication and restoration without AWS. Run `python3 Tests/PartsCatalogTests.py` (requires ffprobe and local audio) to verify prepared parts.

The engine boundary, threading rules, and migration checks are described in [Docs/audio-core.md](Docs/audio-core.md).

Run native UI tests with `Scripts/test_simulator.sh <iPad Simulator UDID>`. Results and physical-device limitations are recorded in [VALIDATION.md](VALIDATION.md).

## Sample provenance

See [Samples/README.md](Samples/README.md). The audio remains separate from the source code's ownership and is not presented as freely licensed sample content. Earlier Git history may still contain prior copies of these files.

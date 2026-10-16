# Breakwater

A native iPad instrument and a static browser player for percussion loops. The native app supports MIDI-synchronized synth jams on iPadOS 17+, designed for an A12 iPad. The bundled library has 222 loops across 13 song pages: the original 60 Niagara cuts plus 162 loops from the percussion audition shortlist. See [the sample catalog](Samples/README.md) for sources and counts.

![Breakwater on iPad](Docs/Design/tablet-landscape.png)

## Performance behavior

- The song picker opens a scrollable list of sources. Selecting a page leaves the arrangement playing, so its steps can combine loops from different songs.
- **Use source** sets the internal tempo to the selected song’s approximate BPM. It is disabled while following MIDI clock, because the external device controls the tempo.
- Drag a pad into the bottom **Sequence** tray: drop it on a step to layer it with that step, or on a plus target to insert another step. The sequence repeats; each step lasts as long as its longest loop, and shorter layers repeat underneath. Tap a pad to replace the arrangement; with the internal clock stopped, the first selection starts immediately. Changes during playback take effect at a four-beat bar boundary. Editing a different step preserves the current phrase; changing the playing step's layers re-cues that step together at the boundary.
- Tap a clip in the tray to select it for Parts. Each clip, including separate copies of the same loop, has its own layer switches and waveform. Remove clips with their × controls, or use **Clear**. An arrangement can contain up to 64 clips, with at most eight in one step. Layers are mixed at reduced levels to leave headroom. Arrangement and Parts settings last for the current session; pad exclusions remain persistent.
- Use **Nudge** in the bottom bar to move the playing loop earlier or later in 10 ms steps; hold either arrow to repeat. The adjustment settles smoothly and follows queued loops. When following MIDI clock, it changes the alignment against the master without changing its tempo or the saved latency setting. Switching clock modes clears the MIDI nudge adjustment.
- `Edit pads` toggles persistent exclusions. Disabled pads remain visible so they can be restored. They cannot be launched by touch or MIDI and are removed from cycles. Disabling the playing pad changes to the next valid selection on a bar boundary; if none remains, playback fades out.
- **Tape** follows tempo by changing playback rate and pitch together.
- **Slice** schedules precomputed drum transients against the beat clock, plays their attacks at original pitch, and uses short crossfades / decaying tail extension. It preserves the original internal swing, rather than quantizing every hit to a rigid subdivision. Extreme tempo changes can reveal slicing artifacts.
- Open **Parts & FX** to see both the selected clip's parts and the output filter together. The tray makes room by resizing the grid; filter choices are Off, low-pass, band-pass and high-pass, with a smoothed cutoff.
- Parts offers four approximate layers: Low, Body, Attack and High. Use **All off** and bring them in one by one, or switch individual layers while playing. Waveform lanes dim when their layers are muted. The labels describe the analysis rather than reliably naming individual instruments: the separation can contain bleed or artifacts, particularly when drums overlap. The unmodified original plays when all four layers are on.

## MIDI and audio

Connect the clock source's MIDI OUT to the CME U2MIDI Pro's white **TO MIDI OUT** plug; connect its USB end to the iPad through Apple's USB camera adapter. Audio goes separately from the iPad's headphone output or an audio interface to your mixer.

Select the MIDI source and enable external clock in Settings. Incoming MIDI Clock, Start, Stop, Continue and Song Position Pointer are supported. Start establishes bar one; Align downbeat can establish it when joining a running jam. Note numbers 36–65 trigger pads 01–30 on the displayed song page; removed pad numbers remain unmapped (Can You See? starts with pad 07 at note 42). Held notes form a sequence that remains after release. Notes are accepted on all channels.

Clock smoothing and a phase correction loop reject small timing jitter without jumping the sample cursor. Tempo changes slew over roughly 90 ms, in addition to the short incoming-clock measurement window. If clock vanishes, playback briefly freewheels; after two seconds it fades out and waits for transport restart. The latency offset advances playback for positive values. Physical timing should be calibrated against the actual audio output.

The app requests a 256-frame audio buffer at 48 kHz; iPadOS chooses the available hardware configuration. Original loops load before playback. Separated layers are decoded off the audio thread as needed and kept in a small cache. While a playing loop's layers are preparing, its full mix continues unless all layers are off, in which case it fades to silence; the Parts tray reports preparation and offers a retry on failure. Rendering uses owned in-memory PCM and a bounded single-producer command ring; the render callback performs no file I/O, locks, allocation, or Swift UI work. Audio can continue in the background. Audio interruptions stop playback; a disconnected output requires a deliberate restart.

## Browser player

Run locally with Python 3; no npm install or bundler is required:

```sh
python3 Scripts/serve_web.py
# Open http://127.0.0.1:8765/
```

The browser version uses the same arrangement, song pages, waveform previews, next-bar changes, timing nudges, and persistent pad exclusions. Drag from the grid to the sequence; on touch screens, hold briefly before dragging. Keyboard users can navigate pads with the arrow keys and activate with Enter/Space; Shift adds a step, and Alt adds a layer to the selected step. On small screens the grid scrolls vertically and the bottom transport stays visible.

Enter a tempo, use **Tap tempo**, or **Use source**. Pitch follows speed, with smoothly changing tempo and short transition fades. There is no MIDI or Slice mode in this version. Only selected loops download and decode when first triggered; subsequent plays use the in-memory cache. Rapid selections share in-flight downloads, and failed clips can be retried without reloading successful clips. Playback then runs in an AudioWorklet on the audio thread, independently of animation and main-thread timers. Browser interruptions require pressing Play again. Preferences belong to this browser and are separate from the native app.

Use a current browser with AudioWorklet support. HTTPS or localhost is required; opening `index.html` as a local file does not work. Mobile browsers can suspend audio in the background or when the device locks. Physical iPad/browser background behavior remains unverified.

### GitHub Pages

1. Create/push this repository under your personal GitHub account, with `main` as the branch.
2. In **Settings → Pages → Build and deployment → Source**, choose **GitHub Actions**.
3. Push to `main`, or run **Deploy web player to GitHub Pages** in the Actions tab after enabling Pages.

The workflow tests the JavaScript engine, builds `build/web`, uploads only the static site, and deploys it. For `dustMason/breakwater`, the expected address is `https://dustmason.github.io/breakwater/`. No custom domain or base-path configuration is needed: all module, icon, catalog and WAV URLs are relative. No credentials or environment secrets are needed beyond the workflow's scoped `GITHUB_TOKEN`.

**Publishing scope:** this site includes the sample WAVs. A Pages site on a personal account is public even if the source repository is private. GitHub Pages from a private personal repository requires GitHub Pro. These files remain subject to the sample provenance described below. See [GitHub's Pages visibility guidance](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site) and [plan availability](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages).

To build for another static host:

```sh
python3 Scripts/build_web.py --output build/web
node --test Tests/Web/*.test.js
```

Serve the contents of `build/web` with JavaScript module MIME types. The web source is in `Web/`; samples are copied from `Samples/` and the favicon/touch icon is the existing native app icon. The build does not expose native source files, development briefs, or repository metadata.

## Build

See [INSTALL.md](INSTALL.md) for the first physical iPad run and MIDI hookup.

Open `Breakwater.xcodeproj` in Xcode. Select the **Breakwater** scheme, choose your personal Apple development team under Signing & Capabilities, and select the iPad or an iPad Simulator. The app requires no package downloads. Apple signing is separate from the GitHub commit identity.

The committed Xcode project can be regenerated with `python3 Scripts/generate_project.py`. The WAV files, compressed parts and `Samples/catalog.json` are already prepared; Python audio-analysis dependencies are not required to build the app. To redo the experimental analysis after changing loops, install NumPy, SciPy, SoundFile and ffmpeg, then run `python3 Scripts/separate_parts.py`. This does not use a pretrained instrument classifier; it groups spectral components separately for each loop.

## Checks

```sh
Scripts/test_core.sh
Scripts/test_interactions.sh
```

The first compiles the portable audio engine with AddressSanitizer and UndefinedBehaviorSanitizer. It tests bar-boundary changes, layered steps, exclusions, clock jitter, tempo steps, phase lock, clock loss, MIDI transport, pitch behavior, per-clip muting and output filters. The second tests MIDI parsing and every shipped sample's format and metadata. Run `npm test` for the browser engine and `python3 Tests/PartsCatalogTests.py` (requires ffprobe) to verify the prepared layer files.

Run native UI tests with `Scripts/test_simulator.sh <iPad Simulator UDID>`. Results and physical-device limitations are recorded in [VALIDATION.md](VALIDATION.md).

## Sample provenance

See [Samples/README.md](Samples/README.md). The WAVs are committed directly for this initial version. They remain separate from the source code's ownership and are not presented as freely licensed sample content.

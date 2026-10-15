# Breakwater

A native iPad instrument and a static browser player for percussion loops. The native app supports MIDI-synchronized synth jams on iPadOS 17+, designed for an A12 iPad. The bundled library has 222 loops across 13 song pages: the original 60 Niagara cuts plus 162 loops from the percussion audition shortlist. See [the sample catalog](Samples/README.md) for sources and counts.

![Breakwater on iPad](Docs/Design/tablet-landscape.png)

## Performance behavior

- The song picker opens a scrollable list of sources. Selecting a page never stops the audio; tap a pad to queue a loop from that song.
- **Use source** sets the internal tempo to the selected song’s approximate BPM. It is disabled while following MIDI clock, because the external device controls the tempo.
- Tap a pad to replace the current loop on the next four-beat bar boundary. With internal clock stopped, tapping starts that pad immediately.
- Hold one pad and touch additional pads to form an ordered cycle. The cycle stays latched when you release your fingers. Each selected sample plays its full one-, two-, or four-bar length, then the next sample plays. The next fresh gesture replaces the cycle at the next bar.
- `Edit pads` toggles persistent exclusions. Disabled pads remain visible so they can be restored. They cannot be launched by touch or MIDI and are removed from cycles. Disabling the playing pad changes to the next valid selection on a bar boundary; if none remains, playback fades out.
- **Tape** follows tempo by changing playback rate and pitch together.
- **Slice** schedules precomputed drum transients against the beat clock, plays their attacks at original pitch, and uses short crossfades / decaying tail extension. It preserves the original internal swing, rather than quantizing every hit to a rigid subdivision. Extreme tempo changes can reveal slicing artifacts.

## MIDI and audio

Connect the clock source's MIDI OUT to the CME U2MIDI Pro's white **TO MIDI OUT** plug; connect its USB end to the iPad through Apple's USB camera adapter. Audio goes separately from the iPad's headphone output or an audio interface to your mixer.

Select the MIDI source and enable external clock in Settings. Incoming MIDI Clock, Start, Stop, Continue and Song Position Pointer are supported. Start establishes bar one; Align downbeat can establish it when joining a running jam. Note numbers 36–65 trigger pads 01–30 on the displayed song page; removed pad numbers remain unmapped (Can You See? starts with pad 07 at note 42). Note release latches the selection, like finger release. Notes are accepted on all channels.

Clock smoothing and a phase correction loop reject small timing jitter without jumping the sample cursor. Tempo changes slew over roughly 90 ms, in addition to the short incoming-clock measurement window. If clock vanishes, playback briefly freewheels; after two seconds it fades out and waits for transport restart. The latency offset advances playback for positive values. Physical timing should be calibrated against the actual audio output.

The app requests a 256-frame audio buffer at 48 kHz; iPadOS chooses the available hardware configuration. All samples load before playback. Rendering uses owned in-memory PCM and a bounded single-producer command ring; the render callback performs no file I/O, locks, allocation, or Swift UI work. Audio can continue in the background. Audio interruptions stop playback; a disconnected output requires a deliberate restart.

## Browser player

Run locally with Python 3; no npm install or bundler is required:

```sh
python3 Scripts/serve_web.py
# Open http://127.0.0.1:8765/
```

The browser version uses the same song pages, real waveform previews, next-bar replacements, full-length cycles, and persistent pad exclusions. Drag across pads or Shift-click to build a cycle with a mouse; on a tablet, hold one pad while touching more. Keyboard users can navigate pads with the arrow keys and activate with Enter/Space (Shift adds to the cycle). On small screens the grid scrolls vertically; touch taps launch on release so swiping does not trigger samples. The bottom transport stays visible.

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

The committed Xcode project can be regenerated with `python3 Scripts/generate_project.py`. The WAV files and `Samples/catalog.json` are already prepared; the Python audio-analysis dependencies are not required to build the app.

## Checks

```sh
Scripts/test_core.sh
Scripts/test_interactions.sh
```

The first compiles the portable audio engine with AddressSanitizer and UndefinedBehaviorSanitizer. It tests bar-boundary replacements, full-length cycles, exclusions, clock jitter, tempo steps, phase lock, clock loss, MIDI transport, and pitch behavior. The second tests gesture latching, MIDI parsing, and every shipped sample's format and metadata.

Run native UI tests with `Scripts/test_simulator.sh <iPad Simulator UDID>`. Results and physical-device limitations are recorded in [VALIDATION.md](VALIDATION.md).

## Sample provenance

See [Samples/README.md](Samples/README.md). The WAVs are committed directly for this initial version. They remain separate from the source code's ownership and are not presented as freely licensed sample content.

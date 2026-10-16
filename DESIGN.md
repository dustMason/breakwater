---
name: Breakwater
description: A native iPad loop instrument whose real waveforms are the performance surface.
colors:
  tint-light: "rgb(0% 32% 84%)"
  tint-dark: "rgb(38% 67% 100%)"
  playing: "rgb(0% 30% 79%)"
  secondary-text-light: "rgb(36% 36% 36%)"
  secondary-text-dark: "rgb(76% 76% 76%)"
  white: "#FFFFFF"
typography:
  title:
    fontFamily: "system-ui"
    fontWeight: 600
  timing:
    fontFamily: "system-ui"
    fontFeature: "'tnum'"
  body:
    fontFamily: "system-ui"
  pad-number:
    fontFamily: "system-ui"
    fontSize: "15pt"
    fontWeight: 600
    fontFeature: "'tnum'"
  pad-bars:
    fontFamily: "system-ui"
    fontSize: "12pt"
    fontWeight: 400
  pad-status:
    fontFamily: "system-ui"
    fontSize: "11pt"
    fontWeight: 600
rounded:
  pad: "7pt"
spacing:
  tight: "4pt"
  grid-gap: "7pt"
  dock-vertical: "8pt"
  pad-inset: "10pt"
  grid-margin: "12pt"
  dock-margin: "16pt"
  header-margin: "18pt"
  dock-gap: "20pt"
components:
  song-menu:
    typography: "{typography.title}"
    height: "44pt"
  waveform-pad:
    rounded: "{rounded.pad}"
    typography: "{typography.pad-number}"
  waveform-pad-playing:
    backgroundColor: "{colors.playing}"
    textColor: "{colors.white}"
    rounded: "{rounded.pad}"
  waveform-pad-queued:
    rounded: "{rounded.pad}"
  pad-status:
    typography: "{typography.pad-status}"
  transport:
    width: "75pt"
    height: "44pt"
  tempo:
    typography: "{typography.timing}"
    width: "82pt"
    height: "44pt"
  mode-picker:
    width: "150pt"
    height: "44pt"
  settings:
    size: "44pt"
  timing-offset:
    typography: "{typography.body}"
---

# Design System: Breakwater

## Overview

**Creative North Star: "The playable waveform grid"**

The samples themselves occupy the screen. Breakwater extends the existing audition player's crisp surface, hairline grid and strong blue playback field into a native iPad instrument. The waveform is both a recognizable sound and a directly playable control; the moving phase sweep makes the current sound visible.

The interface is flat, dense and functional. Native SF typography, semantic light/dark surfaces and system controls surround custom UIKit pads. Color identifies musical state; geometry comes from actual sample data. There is no decorative texture or illustration in the performance surface.

**Key Characteristics:**
- Real PCM waveform geometry is the primary visual content.
- Blue identifies active playback and ordered queue state.
- Native controls, Dynamic Type and semantic appearance provide the surrounding interface.
- A scalable song dropdown and bottom transport preserve space for playable pads.

This is an extraction of `App/Palette.swift`, `App/GridView.swift`, `App/PadGrid.swift`, `App/SettingsView.swift` and `App/BreakwaterApp.swift`. The world and current surface are recorded in `.impeccable/surfaces/app-gridview-swift.md`; `PRODUCT.md` owns product behavior. The approved reference is `Docs/Design/approved-mockup-c.png`, with the user's explicit dropdown substitution. Frontmatter values are app-owned tokens; native points are logical layout units. `system-ui` represents Apple's native SF system font. Semantic platform values and Dynamic Type scaling remain native responsibilities, rather than frozen CSS approximations.

## Colors

The palette uses a restrained blue family on semantic neutral surfaces, with an opaque secondary text role for small labels.

The sidecar's synthesized tonal ramps are panel aids, not additional app colors. Its HTML snippets illustrate the native roles; they do not define shipping web components.

### Primary

- **Instrument blue:** `tint-light` and `tint-dark` are the appearance variants of `Palette.tint`. They color controls, queued waveform ink, status labels and edit outlines.
- **Playing blue:** `playing` is the fixed, darker active-pad field in both appearances. The waveform, labels and playhead use `white` against it.

### Neutral

- **Secondary text:** `secondary-text-light` and `secondary-text-dark` are the opaque `Palette.secondaryText` variants. Use this role for source, bar-length and transport captions, settings guidance and exclusion status.
- **Native surfaces and ink:** preserve UIKit `systemBackground`, `secondarySystemBackground`, `label`, `secondaryLabel`, `tertiaryLabel` and `separator`. These are semantic roles resolved by the operating system; the frontmatter deliberately does not replace them with fixed color snapshots. `secondaryLabel` is waveform art, not the small-text role.
- **White:** active labels, waveform and playhead use the fixed white token. The phase fill uses this color at 14% opacity.

Queued pads use the current instrument tint at 10% opacity behind full-tint ink. Their pending pulse adds a 12% tint layer. Queue borders use 40% tint; editing borders use 50% tint; ordinary borders use the native separator with alpha set to 30%. Excluded pads use `secondarySystemBackground` and tertiary ink for their number, waveform and prohibition symbol. Loading pads reduce their whole-view opacity to 45%.

Stop uses native SwiftUI red while playing. Clock states at or beyond freewheel use native orange; normal clock status uses instrument blue. Preserve these native semantic assignments rather than inventing a separate warning palette.

**The Readable Metadata Rule.** Small informational text uses the opaque adaptive secondary text role; reserve secondary and tertiary system ink for the waveform and exclusion treatments that actually use them.

## Typography

**Display and Body Font:** Apple's native SF system family; no imported display face.
**Timing Numerals:** native monospaced digits within the system face, not a separate monospace typeface.

The hierarchy is compact and functional. SwiftUI text styles scale through Dynamic Type. The custom pad labels use `UIFontMetrics` with explicit maximum sizes so the thirty-pad surface remains usable.

| Role | Native implementation | Application |
| --- | --- | --- |
| Title | `.title2.weight(.semibold)` | Single-line song name; title token does not prescribe a fixed point size. |
| Timing | `.title2.monospacedDigit()` | Source BPM and dock tempo; the tempo form uses `.title.monospacedDigit()`. |
| Body | `.body`, `.callout`, native Form defaults | Edit control, editing hint and settings content. |
| Transport | `.headline` | Play/Stop label. |
| Metadata | `.caption2.weight(.medium)` | SOURCE BPM and TEMPO/CLOCK labels. |
| Clock status | `.caption.weight(.semibold)` | Native icon and clock state. |
| Pad number | `pad-number`, scaled as `.subheadline` | Monospaced digits; maximum 23 points. |
| Pad bar length | `pad-bars`, scaled as `.caption1` | Maximum 19 points; accessibility categories shorten “bars” to “b”. |
| Pad status | `pad-status`, scaled as `.caption2` | Maximum 16 points; playing, ordered queue and exclusion state. |

Do not impose custom line heights or tracking on native controls: none is set by the implementation. Uppercase captions are short operational labels, not a general-purpose eyebrow or heading style.

## Layout

The main view is a native vertical composition: compact header, expanding pad grid, optional loading/editing feedback, divider, then bottom transport. It respects the surrounding native safe area. The song Menu wraps a Picker so the library can grow without adding tabs; source BPM stays at the header's trailing edge.

The grid chooses six columns when its own width is greater than 1.12 times its height, otherwise five. Rows are `ceil(sampleCount / columns)`. With thirty loops this yields the intended landscape 6×5 and portrait 5×6 arrangements. Each pad receives an equal share after subtracting `grid-gap`; the decision uses the available grid bounds, not a device-name or orientation check.

The header uses `header-margin` horizontally, `tight` vertically, a 12-point inter-item gap and a 9-point song-label/chevron gap. The grid has `grid-margin` side margins and 10 points below. The normal dock uses `dock-margin` horizontally, `dock-vertical` vertically and `dock-gap` between controls. Its vertical separators are 34 points tall. The segmented picker is capped at 230 points wide in this layout.

At an available view width below 720 points, or at any accessibility Dynamic Type size, the dock uses two rows. Transport, tempo and clock occupy the first; mode, edit and settings occupy the second. Rows are separated by `tight`, with 6-point vertical dock padding. This accessibility condition applies even on a wide iPad.

Pad content uses `pad-inset` horizontally and a 5-point label top inset. The label band is at least 22 points or the number font's line height. The status frame is 20 points high, 23 points from the lower edge. The waveform starts 4 points below the label band and has at least 12 points of height. These are implemented local geometry rules, not spacing prescriptions for unrelated native forms.

## Elevation & Depth

The app adds no custom shadows. Thin borders, native grouped form surfaces and tonal state fills provide separation. The active blue field is a state change, not a raised card. Sheets, menus and system control materials retain their platform-provided presentation and depth.

## Shapes

Pads are clipped rectangles with the `pad` corner radius and a 0.75-point border. Their waveform is a closed, vertically mirrored path derived from the sample envelope; it is not a set of decorative bars. The playhead is a 1.5-point vertical line. The excluded marker is a 17-point native `nosign` symbol. Native segmented controls, buttons, sliders and sheets retain platform shapes; no app-specific radius is assigned to them.

## Components

### Song menu and source tempo

The song name and native chevron form one Menu control with a minimum 44-point height. A native Picker lists song and artist. The menu's accessibility label names the selected song. Source BPM combines a short caption and approximate numeric value into one accessibility element. Keep the approved dropdown; the illustrative comp's two tabs are not the implementation contract.

### Waveform pads

Each pad exposes a button accessibility role and its loop number, duration and state. Active pads also expose selected state. Excluded pads outside editing, and pads before loading completes, expose not-enabled state. Accessibility custom actions add a step or layer, or exclude or restore a pad. UIKit handles pad taps and drags at the grid level; the child pad is a drawing and accessibility surface.

- **Ready:** native background and label ink, secondary waveform, no status text.
- **Playing:** fixed playing-blue field, white waveform and text, white phase fill and vertical playhead; status reads PLAYING with cycle order when present.
- **Queued:** pale tint field, tinted waveform and number, order plus NEXT BAR while pending, or CYCLE after launch. The state is communicated in words and order, as well as color.
- **Excluded:** muted semantic surface, tertiary waveform and prohibition symbol; EXCLUDED becomes RESTORE during editing.
- **Editing:** blue border treatment and EXCLUDE/RESTORE status make the action explicit.
- **Loading:** pad opacity is reduced and playback interaction is unavailable.

The pending queue pulse animates opacity from zero to one over 0.55 seconds, autoreverses and repeats indefinitely. Reduce Motion suppresses that animation; the queue's textual state and static tint remain. Playback progress directly sets fill width and playhead position from the current clamped phase, with implicit Core Animation actions disabled during updates. It is not a decorative timed sweep.

**The State Has Words Rule.** Preserve the PLAYING, NEXT BAR, CYCLE and exclusion labels and their accessibility values when changing visual state treatments.

### Bottom transport

Play/Stop uses a native Label with an SF Symbol. Its action is disabled while loading; Stop is red during playback. Tempo opens its own native form. Clock status opens settings and distinguishes internal, waiting, locked, freewheel and clock-lost states. Tape/Slice uses the native segmented Picker. Edit pads changes to Done during exclusion editing. Settings uses the native gear symbol with a spoken Settings label.

The minimum target frames are recorded in the frontmatter. Clock and edit also have a 44-point minimum height. Preserve the two-row accessibility layout and native focus/accessibility behavior; there is no custom hover, focus-ring or pressed-animation system in the app.

### Two stacks and sound controls

The Library sits to the left of side-by-side A and B stacks. A clear side label, count and ADD HERE cue show where a library tap will place the next loop. Dropping a library row onto a stack explicitly selects its side. Stacks scroll when needed; the A–B crossfader sits directly below them, above the master transport.

Clip rows are contiguous and contain a stylized waveform, independent four-part switches, a center-detented low/high-pass filter and a vertical level fader. Waveform strokes maintain a fixed spacing; wider previews display more samples of the envelope. Blue denotes a running clip, its playhead shows phase within the waveform preview, and an outline identifies selection. The master filter remains in the bottom bar. Maintain 44-point touch targets and accessible labels for stack, clip and crossfader controls.

### Settings and tempo sheets

Both surfaces use native NavigationStack, Form sections and a Done confirmation action. Settings includes clock following, MIDI input selection, timing offset, playback mode, audio output and pad guidance. The timing slider spans −200 to +200 ms in 1 ms steps. Tempo uses a 30–300 BPM stepper and slider, plus a full-width Tap tempo button with a 60-point minimum height. Its sheet supports native medium and large detents. These numeric domains are the implemented controls' contracts, not global design tokens.

Native Toggle, Picker, Slider, Stepper and Button behavior supplies focus, accessibility and interaction states. There is no custom text-entry field or bespoke modal surface to reproduce. Connection guidance refers to the synth or sequencer's MIDI OUT port, avoiding ambiguous adapter-cable naming.

### Evidence and review scope

The recorded native captures are `.impeccable/review/tablet-landscape.png`, `.impeccable/review/tablet-portrait.png`, `.impeccable/review/tablet-settings.png` and `.impeccable/review/tablet-dark-large.png`. `.impeccable/review/finish-review.md` records an initial fix verdict and the final scoped ship verdict. The final pass resolved small secondary text contrast and MIDI connection wording; sampled light secondary text measured 6.69:1 on white. This is a review of supplied Simulator captures and the fix batch, not blanket hardware approval or a claim that every state was captured.

`VALIDATION.md` owns build, test and hardware evidence. The captures use an A16 iPad Simulator on iOS 27; the A12 device and iPadOS 17 runtime remain untested. Physical multi-touch, MIDI/audio routing, output latency, A12 performance and audible Slice quality remain open. The browser-only plan/asset approval gate remains open; no browser detector ran for the native UIKit/SwiftUI surface and no approval receipt was fabricated. This documentation pass adds no validation evidence.

## Do's and Don'ts

### Do:
- **Do** derive waveform geometry and progress from actual sample and playback data.
- **Do** use the adaptive secondary text role for small informational copy.
- **Do** preserve native Dynamic Type, semantic appearance and button accessibility roles.
- **Do** retain ordered state text alongside blue playback and queue treatments.
- **Do** let the dropdown scale with the song library and keep performance controls at the bottom.

### Don't:
- **Don't** restore the comp's song tabs in place of the approved dropdown.
- **Don't** replace real waveform geometry with decorative artwork.
- **Don't** freeze semantic surfaces or Dynamic Type into screenshot-specific values.
- **Don't** add custom shadows, texture or display-font styling to this flat native instrument.
- **Don't** treat Simulator captures, documentation or the scoped ship verdict as physical-device verification.

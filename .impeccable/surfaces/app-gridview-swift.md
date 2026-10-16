---
version: 1
slug: "app-gridview-swift"
primary_target: "App/GridView.swift"
related_targets: []
---

# Library and two stacks
Mode: Operate. Target: App/GridView.swift. iPad landscape and portrait.

## Direction contract
THESIS: Browse real loop waveforms in song folders and blend two independently looping stacks.
OWN-WORLD: Continue the established crisp semantic surfaces, thin rules, native SF text, monospaced timing numerals and strong blue playback state. Real waveform geometry remains the visual content; no decorative texture or illustration is introduced.
STORY: Tap a loop to add it to the quieter side, or drag to A or B; shape each clip and crossfade the running stacks.
FIRST VIEWPORT: A scrollable Library sits left of side-by-side A and B stacks; a crossfader sits below them and transport remains at the bottom. Contiguous clip rows carry waveforms, four part switches, a filter knob and vertical level fader.
FORM: Extend the established waveform-instrument world with two concurrent stacks and a direct crossfader; preserve the existing neutral surfaces, blue playing treatment and touch-sized controls.
FINISH: The A/B redesign was checked in a muted desktop browser; the native simulator is currently unavailable because CoreSimulator and Xcode versions do not match. Earlier captures below are historical.


## Current A/B stack extension — 2026-10-16

Each side holds up to eight concurrently looping clips; clips added during playback start at the next bar while retained clips keep phase. Crossfade position determines the quieter side for library taps; a centered tie uses the less-populated side and then A. Dragging targets either side explicitly. Four part switches start enabled for each new clip.

## Historical timeline extension — 2026-10-15
This section is superseded by the A/B stack extension above.
The Library expands song folders to reveal numbered waveform rows and loop lengths. The Add menu sets the tap action to add at the end, insert before or after the selected step, or add a layer; dragging a row places it directly. Named accessibility actions offer the insert and layer choices. Edit changes row activation to exclude or restore a loop. The header's Use source applies the active folder's source BPM and is disabled under external MIDI clock.

Steps run horizontally, with widths proportional to the longest clip in each step subject to a minimum width for the controls. Drop at a step edge or plus margin to insert; drop beneath the clips to layer. Shorter clips repeat across the step and their waveform repeats visually. The timeline scrolls in both directions as needed and offers zoom, Fit and Clear; tapping a waveform selects a clip, and its remove control is separate. The selected outline, active blue fill and moving playhead communicate distinct states.

Each clip directly presents a 2×2 grid of part switches, an all-parts switch, a center-bypass LPF/HPF knob and a vertical level fader. Waveforms use simple strokes for the enabled parts over a faint original. The separately labeled master filter sits in the bottom transport bar and continues to offer Off, LPF, BPF and HPF with an independent cutoff. Accessible controls expose labels and state; the separated parts are estimates and can overlap.

The earlier timeline documentation pass checked `App/GridView.swift`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/design.json`, the prior surface contract, and `.impeccable/review/timeline-ipad-landscape.png` and `timeline-ipad-portrait.png`. Those captures predate the bottom rack. `VALIDATION.md` owns current functional and hardware evidence.

`DESIGN.md` and `.impeccable/design.json` still describe the earlier song dropdown and pad grid in places. That pre-existing shared-document drift was observed and left unchanged; this brief records the current surface.

## Earlier surface history
The original approved comp was `.impeccable/mocks/option-c.png`, with the user's dropdown substitution for song tabs. The following dated sections describe the prior grid and arrangement-tray iterations and are superseded where they conflict with the timeline contract above.

### Parts and filter extension — 2026-10-15
The header opens a closeable side tray beside the reflowing waveform grid. Parts exposes four per-song approximate layers, individual ON/OFF controls and All on / All off; the layer description acknowledges overlap. Opening Parts, or leaving any layer off, shows four waveform lanes per pad, with muted lanes dimmed. FX opens a Filter tray with Off, LPF, BPF and HPF choices and a labeled cutoff slider. The neutral surfaces, blue state cues, native controls and playback sweep retain the established grid identity.

The documentation pass checked `App/GridView.swift`, `App/PadGrid.swift`, and the A16 iPad Simulator captures `build/features-final/1088507F-1A01-43DA-BE0C-457127377CE5.png` (landscape Parts, Low off) and `build/features-final/0259FAAF-08BC-4098-BD5C-27438F990FAD.png` (portrait Filter). The independent visual review reported the native off-button contrast fix resolved and a ship verdict at that scope; the muted waveform remains dim. `VALIDATION.md` records functional checks and their limits. These captures do not establish physical iPad behavior or audible separation quality.

### Arrangement extension — 2026-10-15
The bottom sequence tray replaces pad-chord chaining: drop a sample on a step to layer it, or on a plus target to insert a step. Rows identify and select individual clips for Parts; shorter layers repeat until the step's longest clip ends. The arrangement remains when changing songs. The side panel presents the selected clip's Parts and the global filter together. This supersedes the earlier per-song Parts and separate tray description above. Visual and functional evidence for this extension is recorded in `VALIDATION.md`; physical iPad touch, live MIDI and audible quality remain unverified.

The finish review inspected the muted A16 Simulator portrait arrangement and landscape Parts/Filter captures. The song and tempo, grid, selected Parts, filter, sequence and transport remain legible at those sizes; multi-row steps scroll within the tray. The review found no layout blocker at the captured sizes. Dynamic Type extremes and the user's physical iPad remain outside that review.

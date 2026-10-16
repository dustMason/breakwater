---
version: 1
slug: "web-index-html"
primary_target: "Web/index.html"
related_targets: ["Web/app.js","Web/style.css"]
---

# Browser library and two stacks
Mode: Operate. Static HTML/CSS/JavaScript port of the approved native performance surface; desktop, tablet and small screens.

## Direction contract
THESIS: Browse real loop waveforms in song folders and blend two independently looping stacks.
OWN-WORLD: Continue the established neutral surfaces, system typography, thin borders, blue playback state, real waveforms and approved B icon.
STORY: Tap a loop to add it to the quieter side, or drag to A or B; shape each clip and crossfade the running stacks.
FIRST VIEWPORT: A scrollable Library sits left of side-by-side A and B stacks; a crossfader sits below them and transport remains at the bottom. Contiguous clip rows carry waveforms, four part switches, a filter knob and vertical level fader.
FORM: Extend the established waveform-instrument world with two concurrent stacks and a direct crossfader; preserve the existing neutral surfaces, blue playing treatment and touch-sized controls.
FINISH: The A/B redesign was checked in a muted desktop browser; the native simulator is currently unavailable because CoreSimulator and Xcode versions do not match. Earlier captures below are historical.


## Current A/B stack extension — 2026-10-16

Each side holds up to eight concurrently looping clips; clips added during playback start at the next bar while retained clips keep phase. Crossfade position determines the quieter side for library taps; a centered tie uses the less-populated side and then A. Dragging targets either side explicitly. Four part switches start enabled for each new clip.

## Constraints
Static hosting only; local preview uses an ordinary HTTP server. Web Audio runs on the audio thread, keeps phase during tempo changes, and handles context interruptions explicitly. No automatic audio playback. The established visual design system remains unchanged while the native and web timeline evolve together.

## Historical timeline extension — 2026-10-15
This section is superseded by the A/B stack extension above.
The Library expands song folders into numbered waveform rows and loop lengths. Activating a row adds it at the end; dragging places it directly. Keyboard activation and Alt/Option shortcuts provide layer and before/after placement relative to the selected step. Edit makes row activation exclude or restore a loop. The current source BPM remains visible, with Use source in the dock.

Steps run horizontally and their widths follow the longest clip in each step, subject to a minimum width for the controls. Drop at a step edge or plus margin to insert; drop beneath the clips to layer. Shorter clips repeat across the step and their waveform repeats visually. Zoom, Fit and Clear sit above the scrolling timeline. A waveform selects a clip and a separate control removes it. Selection, active playback and playhead progress have distinct visual treatments.

Each clip directly presents a 2×2 grid of part switches, an all-parts switch, a center-bypass LPF/HPF knob and a vertical level fader. Waveforms use simple strokes for the enabled parts over a faint original. The separately labeled master filter sits in the bottom transport bar and continues to provide Off, LPF, BPF and HPF with an independent cutoff. The browser retains focus-visible outlines and explicit accessible labels alongside the native adaptation.

The earlier timeline documentation pass checked `Web/index.html`, `Web/style.css`, `Web/app.js`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/design.json`, the prior surface contract, and `.impeccable/review/timeline-desktop.png` (1280×720), `timeline-tablet-web.png` (820×1180), `timeline-phone.png` and `timeline-phone-inspector.png` (both 390×844). Those captures predate the bottom rack. `VALIDATION.md` owns current functional and hardware evidence.

`DESIGN.md` and `.impeccable/design.json` still describe the earlier song dropdown and pad grid in places. That pre-existing shared-document drift was observed and left unchanged; this brief records the current surface.

## Earlier surface history
The following sections document the previous grid and arrangement-tray iterations. Their layout and interaction descriptions are superseded where they conflict with the timeline contract above.

### Implemented browser adaptation
The shipped surface retains the playable waveform grid, song dropdown, bottom transport, 7px pad radius and grid gap, flat borders, blue musical states and explicit PLAYING / NEXT BAR / CYCLE / exclusion text. System fonts and tabular numerals carry the native hierarchy into CSS. Browser light/dark color values, rem-based labels, focus outlines and form controls are platform adaptations; they do not replace native semantic colors, Dynamic Type or the app-owned tokens in `DESIGN.md`.

Grid width below 460px uses three columns; below 650px it uses four. Wider grids preserve the native six-column test (`width > height × 1.12`), otherwise five. Rows remain at least 88px high, allowing the grid to scroll while the transport stays visible. At 720px and below, the dock uses a compact three-row arrangement and hides the header icon and artist. Inline tempo, tap/source tempo and volume replace the native settings/mode controls for this browser scope; MIDI and slicing are absent.

### Finish evidence
The documentation pass checked `Web/index.html`, `Web/style.css`, `Web/app.js`, audio implementation, `App/Palette.swift`, `App/GridView.swift`, `PRODUCT.md`, `DESIGN.md` and `.impeccable/design.json`. It opened `.impeccable/review/web-desktop.png` (1440×900), `web-tablet.png` (820×1180) and `web-mobile.png` (390×844): all retain the waveform-first hierarchy and visible bottom transport. `.impeccable/review/web-finish-review.md` records **ship**, with no material fixes. These are source/capture checks, not a new physical-touch, audible-quality or publication claim.

`DESIGN.md` and `.impeccable/design.json` remain unchanged and native-authoritative. The historical native evidence paragraph's open browser plan/asset-gate wording predates this adaptation; this surface's review record owns the browser finish disposition. That historical wording was not repaired or promoted into a new design rule.

### Sample-library expansion
The October 14 percussion pass adds twelve song pages without changing the composition or CSS. Playback fetches only selected clips and shares in-flight decodes between rapid gestures. Per-song timing ranges and interpretation notes are available on the source-BPM tooltip. `VALIDATION.md` records the catalog, audio, OP-1 and browser checks.

### Parts and filter extension — 2026-10-15
Parts and FX open a closeable side tray beside the reflowing grid. Parts offers four per-song approximate layers, individual ON/OFF controls and All on / All off; the copy notes possible overlap. Opening Parts, or leaving a layer off, shows four waveform lanes per pad, with muted lanes dimmed. Filter provides Off, LPF, BPF and HPF choices and a labeled cutoff slider. These controls use the existing neutral surfaces, blue states, thin borders and system type. When the tray narrows the grid below 260px, the browser uses two columns.

The documentation pass checked `Web/index.html`, `Web/style.css` and `Web/app.js`, and opened `build/features-final/web-desktop.png` and `build/features-final/web-mobile.png`, which show the Parts tray and grid at desktop and phone sizes. `VALIDATION.md` records the additional browser and audio checks. The captures do not establish audible separation quality or physical-touch performance.

### Arrangement extension — 2026-10-15
The sequence tray shows ordered step cards containing waveform rows. A drop on a card layers a sample; a drop on a plus inserts a step. Clicking a row selects its independent Parts settings. The panel shows Parts and Filter at once, and the sequence remains across song changes. Keyboard activation provides step and layer shortcuts. The muted browser preview was checked for layering, sequencing, cross-song arrangement, independent Parts and keyboard use; `VALIDATION.md` records functional and hardware limits. This supersedes the earlier per-song Parts and separate tray description above.

The finish review inspected the combined panel and layered tray in a 1280×720 muted browser preview. Both sound sections and the transport are visible together; longer grids and stacked clips scroll. No layout blocker was found at that viewport. This is not a physical-touch or audible-quality validation.

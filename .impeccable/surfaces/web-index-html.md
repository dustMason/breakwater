---
version: 1
slug: "web-index-html"
primary_target: "Web/index.html"
related_targets: ["Web/app.js","Web/style.css"]
---

# Browser library and timeline
Mode: Operate. Static HTML/CSS/JavaScript port of the approved native performance surface; desktop, tablet and small screens.

## Direction contract
THESIS: Browse the shared loop catalog by folder and build a playable, layered arrangement on a bar-oriented browser timeline.
OWN-WORLD: Continue the established neutral surfaces, system typography, thin borders, blue playback state, real waveforms and approved B icon.
STORY: Open a song folder, add or drag loops into the timeline, select a clip to shape its sound, change tempo and edit exclusions. Browsing preserves playback.
FIRST VIEWPORT: The source and approximate BPM are in the header; a scrollable Library is left of the Timeline, with the optional Sound device rack beneath the timeline and transport below. Timeline steps contain stacked waveform clips with selection outlines and a blue playing state and playhead. On narrow screens the rack scrolls horizontally and the dock wraps.
FORM: Extend the established waveform-instrument world with the native timeline composition and browser-appropriate controls. No new visual world or comp round. Browser playback omits MIDI and slicing.
FINISH: The supplied independent timeline reviewer scored all five material fixes resolved. The source and capture evidence and its limits are recorded below.

## Constraints
Static hosting only; local preview uses an ordinary HTTP server. Web Audio runs on the audio thread, keeps phase during tempo changes, and handles context interruptions explicitly. No automatic audio playback. The established visual design system remains unchanged while the native and web timeline evolve together.

## Timeline extension — 2026-10-15
The Library expands song folders into numbered waveform rows and loop lengths. Activating a row adds it at the end; dragging places it directly. Keyboard activation and Alt/Option shortcuts provide layer and before/after placement relative to the selected step. Edit makes row activation exclude or restore a loop. The current source BPM remains visible, with Use source in the dock.

Steps run horizontally and their widths follow the longest clip in each step. Drop at a step edge or plus gap to insert; drop in the step to layer. Shorter clips repeat across the step and their waveform repeats visually. Zoom, Fit and Clear sit above the scrolling timeline. Selecting a clip opens Sound; a separate control removes it. Selection, active playback and playhead progress have distinct visual treatments.

Sound presents individual part devices and the selected clip's filter, followed by a separately labeled master filter, in a horizontally scrollable rack beneath the timeline. Both filters provide Off, LPF, BPF and HPF with independent cutoffs. Clip-specific controls are unavailable without a selection; master controls remain available. Parts show ON/OFF labels. The browser retains focus-visible outlines and explicit labels alongside the native adaptation.

The earlier timeline documentation pass checked `Web/index.html`, `Web/style.css`, `Web/app.js`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/design.json`, the prior surface contract, and `.impeccable/review/timeline-desktop.png` (1280×720), `timeline-tablet-web.png` (820×1180), `timeline-phone.png` and `timeline-phone-inspector.png` (both 390×844). Those captures predate the bottom rack. `VALIDATION.md` owns current functional and hardware evidence.

The shared `PRODUCT.md`, `DESIGN.md` and `.impeccable/design.json` still describe the earlier song dropdown, pad grid and its activation behavior in places. That pre-existing shared-document drift was observed and left unchanged; this brief records the current surface.

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

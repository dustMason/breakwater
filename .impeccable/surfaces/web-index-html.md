---
version: 1
slug: "web-index-html"
primary_target: "Web/index.html"
related_targets: ["Web/app.js","Web/style.css"]
---

# Browser performance grid
Mode: Operate. Static HTML/CSS/JavaScript port of the approved native performance surface; desktop, tablet and small screens.

## Direction contract
THESIS: The existing waveform instrument, immediately playable in a browser, using the same sixty committed samples.
OWN-WORLD: Inherit DESIGN.md's neutral surfaces, system typography, thin borders and blue playing/queued states. Reuse the approved B icon.
STORY: Choose a song, tap a loop, change tempo, build a latched cycle, and persistently exclude unwanted pads. Browsing does not interrupt audio.
FIRST VIEWPORT: Compact song dropdown and source BPM above the expanding waveform grid; transport, editable tempo, volume and Edit pads below. Six columns on landscape tablets/desktops, five on portrait tablets, three on narrow phones with the grid scrollable and transport anchored.
FORM: A precisely requested port of the existing approved C/dropdown surface, not a new composition or identity. No new seed or comp round. The audio-phase sweep remains the signature interaction. Add desktop drag/Shift-click gestures. Omit MIDI and slicing.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Constraints
Static hosting only; local preview uses an ordinary HTTP server. Web Audio runs on the audio thread, keeps phase during tempo changes, and handles context interruptions explicitly. No automatic audio playback. Existing native files and design system remain unchanged.

## Implemented browser adaptation
The shipped surface retains the playable waveform grid, song dropdown, bottom transport, 7px pad radius and grid gap, flat borders, blue musical states and explicit PLAYING / NEXT BAR / CYCLE / exclusion text. System fonts and tabular numerals carry the native hierarchy into CSS. Browser light/dark color values, rem-based labels, focus outlines and form controls are platform adaptations; they do not replace native semantic colors, Dynamic Type or the app-owned tokens in `DESIGN.md`.

Grid width below 460px uses three columns; below 650px it uses four. Wider grids preserve the native six-column test (`width > height × 1.12`), otherwise five. Rows remain at least 88px high, allowing the grid to scroll while the transport stays visible. At 720px and below, the dock uses a compact three-row arrangement and hides the header icon and artist. Inline tempo, tap/source tempo and volume replace the native settings/mode controls for this browser scope; MIDI and slicing are absent.

## Finish evidence
The documentation pass checked `Web/index.html`, `Web/style.css`, `Web/app.js`, audio implementation, `App/Palette.swift`, `App/GridView.swift`, `PRODUCT.md`, `DESIGN.md` and `.impeccable/design.json`. It opened `.impeccable/review/web-desktop.png` (1440×900), `web-tablet.png` (820×1180) and `web-mobile.png` (390×844): all retain the waveform-first hierarchy and visible bottom transport. `.impeccable/review/web-finish-review.md` records **ship**, with no material fixes. These are source/capture checks, not a new physical-touch, audible-quality or publication claim.

`DESIGN.md` and `.impeccable/design.json` remain unchanged and native-authoritative. The historical native evidence paragraph's open browser plan/asset-gate wording predates this adaptation; this surface's review record owns the browser finish disposition. That historical wording was not repaired or promoted into a new design rule.

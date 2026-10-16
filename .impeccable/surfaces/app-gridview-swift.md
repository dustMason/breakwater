---
version: 1
slug: "app-gridview-swift"
primary_target: "App/GridView.swift"
related_targets: []
---

# Performance grid
Mode: Operate. Target: App/GridView.swift. iPad landscape and portrait.

## Direction contract
THESIS: The samples themselves occupy the screen; this is a live instrument with thirty directly playable waveform pads per song.
OWN-WORLD: Extend the existing loop player's crisp light surface, hairline grid and strong blue playback field. Native SF text and monospaced timing numerals; semantic dark appearance. No decorative texture or illustration.
STORY: Pick a song, see its source tempo, tap a waveform, then queue a replacement or chord of pads without interrupting the jam. Edit exclusions explicitly.
FIRST VIEWPORT: A song dropdown and approximate source BPM above a 6-by-5 landscape grid; transport dock below. One blue playing pad carries a moving waveform sweep; queued pads flash with order badges. Source BPM remains visible. Approved comp: .impeccable/mocks/option-c.png. User approved C with a dropdown replacing the song tabs. Portrait adapts to five columns.
FORM: User-specified pad grid, inheriting the established audition player's visual world; no new visual-world roll. Signature interaction is the moving audio-phase sweep inside the playing waveform pad.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Parts and filter extension — 2026-10-15
The header opens a closeable side tray beside the reflowing waveform grid. Parts exposes four per-song approximate layers, individual ON/OFF controls and All on / All off; the layer description acknowledges overlap. Opening Parts, or leaving any layer off, shows four waveform lanes per pad, with muted lanes dimmed. FX opens a Filter tray with Off, LPF, BPF and HPF choices and a labeled cutoff slider. The neutral surfaces, blue state cues, native controls and playback sweep retain the established grid identity.

The documentation pass checked `App/GridView.swift`, `App/PadGrid.swift`, and the A16 iPad Simulator captures `build/features-final/1088507F-1A01-43DA-BE0C-457127377CE5.png` (landscape Parts, Low off) and `build/features-final/0259FAAF-08BC-4098-BD5C-27438F990FAD.png` (portrait Filter). The independent visual review reported the native off-button contrast fix resolved and a ship verdict at that scope; the muted waveform remains dim. `VALIDATION.md` records functional checks and their limits. These captures do not establish physical iPad behavior or audible separation quality.

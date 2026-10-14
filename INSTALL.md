# Run Breakwater on your iPad

1. Clone this repository on the Mac and open `Breakwater.xcodeproj`.
2. In Xcode, select the **Breakwater** app target → **Signing & Capabilities**. Choose your personal Apple development team. Leave automatic signing enabled; change the bundle identifier only if Xcode reports it is unavailable to your team.
3. Connect and unlock the iPad. Select it as the run destination, then press Run. Follow the iPad's Developer Mode or trust prompts if shown.
4. Open Breakwater and wait for the bundled samples to load. The current library contains 252 loops across 14 songs, including the revised cuts. Tap a waveform to start. Tap another to switch at the next bar.
5. Connect the USB MIDI adapter through the camera adapter. The plug that receives MIDI from the sequencer connects to the sequencer's MIDI OUT. Connect the iPad's wired audio output separately to your mixer.
6. In Breakwater Settings, enable **Follow MIDI clock** and choose the input. Select a pad and send **Start** from the master. The clock indicator changes to **LOCKED** once timing is established.

The **Tempo** button opens manual tempo and tap tempo when MIDI sync is off. **Tape** changes pitch with speed; **Slice** keeps the attacks at their original pitch. Hold one pad and touch others to build a cycle, then release to latch it. **Edit pads** saves exclusions until you restore them.

Use **Timing offset** to align the loops by ear against the synth: positive values bring the loops earlier. Prefer a wired output for jamming. The physical iPad/adapter timing still needs this first device check.

GitHub author identity and Apple app signing are separate. The repository is committed under dustMason; an Apple development team must be selected locally to install on the iPad.

For sample updates, rebuild and run the app again from this checkout. Both native and web builds read `Samples/catalog.json` and the same WAV files; there is no separate native import step. Install over the existing app to keep saved pad exclusions and settings. Stable pad IDs preserve those choices as the library is curated.

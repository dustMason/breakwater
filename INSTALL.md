# Run Breakwater on your iPad

1. Install the Rust toolchain with rustup, then install the iPad and Simulator targets:

   ```sh
   rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
   ```

   Clone this repository on the Mac. Xcode builds the Rust library automatically. The x86-64 target is needed when Xcode builds a universal Simulator library.
2. Set the HTTPS asset-library address locally, without committing it, then open `Breakwater.xcodeproj`:

   ```sh
   source .asset.env # or export BREAKWATER_ASSET_BASE_URL yourself
   python3 Scripts/configure_assets.py
   open Breakwater.xcodeproj
   ```

   This writes the ignored `App/Config.local.xcconfig`, which the project reads even when Xcode is launched from the Dock. For command-line builds, a `BREAKWATER_ASSET_BASE_URL=...` Xcode build setting also works. The URL is embedded in the app and is visible to its users.
3. In Xcode, select the **Breakwater** app target → **Signing & Capabilities**. Choose your personal Apple development team. Leave automatic signing enabled; change the bundle identifier only if Xcode reports it is unavailable to your team.
4. Connect and unlock the iPad. Select it as the run destination, then press Run. Follow the iPad's Developer Mode or trust prompts if shown.
5. Open Breakwater and wait for the catalog to load. Expand a song folder in the library and tap a loop to download it and add it to the timeline. Drag loops between steps to sequence them or beneath a step to layer them; tap a timeline clip to adjust its parts and filter. Browsing folders does not interrupt playback. Downloaded audio and the last catalog are cached for offline use, subject to iPadOS cache eviction.
6. Connect the USB MIDI adapter through the camera adapter. The plug that receives MIDI from the sequencer connects to the sequencer's MIDI OUT. Connect the iPad's wired audio output separately to your mixer.
7. In Breakwater Settings, enable **Follow MIDI clock** and choose the input. Select a pad and send **Start** from the master. The clock indicator changes to **LOCKED** once timing is established.

The **Tempo** button opens manual tempo and tap tempo when MIDI sync is off. **Use source** sets the internal tempo to the active folder’s approximate BPM; it is disabled while MIDI clock controls tempo. **Tape** changes pitch with speed; **Slice** keeps the attacks at their original pitch. **Edit** in the library saves exclusions until you restore them.

Use **Timing offset** to align the loops by ear against the synth: positive values bring the loops earlier. Prefer a wired output for jamming. The physical iPad/adapter timing still needs this first device check.

GitHub author identity and Apple app signing are separate. The repository is committed under dustMason; an Apple development team must be selected locally to install on the iPad.

For sample updates, publish the library using the README instructions. Both players load the published catalog; restart the app or reload the web page to pick up a new catalog. Install over the existing app to keep saved pad exclusions and settings. Stable pad IDs preserve those choices as the library is curated.

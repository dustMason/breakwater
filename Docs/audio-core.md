# Shared audio core

Breakwater's playback, transport and clock live in `Rust/`. The iPad app links
the Rust static library through `AudioCore/BreakwaterAudio.h`; the web player
loads the same engine as WebAssembly inside its AudioWorklet. The iPad still
owns Core MIDI, audio-session lifecycle and decoding. The browser owns fetch,
decoding, its audio context and user interaction. Preprocessed parts and the
catalog are unchanged.

## Migration and verification

The former C++ engine is retained only as a test oracle under `Tests/Reference`.
The native API and clock behavior are preserved first. A differential harness
runs matching event traces and audio through both implementations; the existing
native behavior tests then run against Rust. Web tests exercise the actual Wasm
build, rather than a separate JavaScript DSP implementation. Browser and iPad
host tests cover loading, device lifecycle, presentation and integration.

## Real-time and ownership contract

The native host serializes control events through a bounded single-producer,
single-consumer command queue (4,095 usable entries); overflow is reported to
the UI. Only the audio callback mutates transport and
voice state. Rendering must not allocate, lock, decode, do I/O or free sample
buffers. Parts are prepared off the callback and installed atomically; old
buffers are reclaimed on the control thread after a completed render block.
Part pointer access, publication and block completion use sequentially
consistent atomics so a retired buffer cannot be freed while a callback can
still observe it. UI snapshots use atomics and a sequence counter to read a
coherent block without locking the audio thread.
Samples are immutable once published. The iPad can decode a sample on a worker
and publish it into an empty bank slot while the callback is running. Slots use
release/acquire publication and are never replaced or freed until the engine
has stopped. The web worklet publishes samples between render callbacks on its
own thread.

The Wasm bridge uses a bounded amount of copying per worklet block when
loading decoded samples or parts, and acknowledges publication before an
arrangement can use a loop. Wasm memory can grow while a sample is prepared,
so JavaScript must refresh views after allocations; pointers into old views
must not be retained. A completed transfer is installed as one immutable bank.
The player continues to use the original mix when every part is enabled.
Preparing the destination allocation and growing Wasm memory still occur in
the worklet; these events can briefly interrupt audio, especially on older
devices. The bounded copy only limits the subsequent transfer work. Shared
memory could move more preparation off-thread, but would require a deployment
with cross-origin isolation, which the current static hosting does not assume.

Native MIDI timestamps and render timestamps must be expressed in the same
monotonic clock domain. Browser manual playback uses the Web Audio sample clock;
adding browser MIDI later will require explicit clock-domain conversion. Neither
the shared algorithm nor simulator checks establish physical MIDI/output
latency or performance on an A12 iPad.

## Host API

`AudioCore/BreakwaterAudio.h` is the native ABI and documents the single
producer, buffer lengths and ownership transfers. The Wasm host additionally
uses `bw_prepare_loop` / `bw_prepare_parts` to fill private planar buffers,
then transfers ownership on installation. The core's Rust FFI entry points
document their pointer and threading requirements. The web bridge asks Rust
for snapshot field offsets rather than assuming a native struct layout.

The original four-field `BWClip` arrangement API remains available. Hosts that
need per-clip filtering use `BWClipWithFilter` with
`bw_arrange_with_filters` / `bw_edit_arrangement_with_filters`, and can update
an instance by token with `bw_clip_filter`. Each live layer owns its filter
state, so two uses of the same loop can have different settings. Filter changes
are smoothed in the audio engine; the separate master filter still processes the
combined output. The extended clip array and filter commands are copied into
the existing bounded command queue, without allocating in the render callback.

//! Shared Breakwater playback engine. The C ABI is used by Swift and Wasm.
mod dsp;
mod engine;
mod sample;
use engine::*;
use sample::{Bank, Parts, Sample, MAX_LOOPS};
use std::cell::UnsafeCell;
use std::ptr;
use std::sync::atomic::{AtomicI32, AtomicPtr, AtomicU32, AtomicU64, AtomicUsize, Ordering};

const RING_SIZE: usize = 4096;
struct Ring {
    entries: Box<[UnsafeCell<Command>]>,
    head: AtomicUsize,
    tail: AtomicUsize,
    dropped: AtomicU32,
}
// SAFETY: exactly one serialized producer and one render-thread consumer.
unsafe impl Sync for Ring {}
impl Ring {
    fn new() -> Self {
        Self {
            entries: (0..RING_SIZE)
                .map(|_| UnsafeCell::new(Command::default()))
                .collect(),
            head: AtomicUsize::new(0),
            tail: AtomicUsize::new(0),
            dropped: AtomicU32::new(0),
        }
    }
    fn push(&self, c: Command) {
        let h = self.head.load(Ordering::Relaxed);
        let n = (h + 1) % RING_SIZE;
        if n == self.tail.load(Ordering::Acquire) {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        unsafe { *self.entries[h].get() = c };
        self.head.store(n, Ordering::Release);
    }
    fn pop(&self) -> Option<Command> {
        let t = self.tail.load(Ordering::Relaxed);
        if t == self.head.load(Ordering::Acquire) {
            return None;
        }
        let c = unsafe { *self.entries[t].get() };
        self.tail.store((t + 1) % RING_SIZE, Ordering::Release);
        Some(c)
    }
}
struct AtomicSnapshot {
    version: AtomicU64,
    beat: AtomicU64,
    bpm: AtomicU64,
    progress: AtomicU64,
    playing: AtomicI32,
    active: AtomicI32,
    mode: AtomicI32,
    external: AtomicI32,
    clock: AtomicI32,
    pending: AtomicI32,
    count: AtomicI32,
    queue: [AtomicI32; MAX_QUEUE],
    active_count: AtomicI32,
    step: AtomicI32,
    loops: [AtomicI32; MAX_LAYERS],
    tokens: [AtomicI32; MAX_LAYERS],
    active_progress: [AtomicU64; MAX_LAYERS],
}
impl AtomicSnapshot {
    fn new() -> Self {
        Self {
            version: AtomicU64::new(0),
            beat: AtomicU64::new(0f64.to_bits()),
            bpm: AtomicU64::new(120f64.to_bits()),
            progress: AtomicU64::new(0),
            playing: AtomicI32::new(0),
            active: AtomicI32::new(-1),
            mode: AtomicI32::new(0),
            external: AtomicI32::new(0),
            clock: AtomicI32::new(0),
            pending: AtomicI32::new(0),
            count: AtomicI32::new(0),
            queue: std::array::from_fn(|_| AtomicI32::new(0)),
            active_count: AtomicI32::new(0),
            step: AtomicI32::new(0),
            loops: std::array::from_fn(|_| AtomicI32::new(0)),
            tokens: std::array::from_fn(|_| AtomicI32::new(0)),
            active_progress: std::array::from_fn(|_| AtomicU64::new(0)),
        }
    }
    fn set(&self, s: &Snapshot) {
        self.version.fetch_add(1, Ordering::AcqRel);
        self.beat.store(s.beat.to_bits(), Ordering::Relaxed);
        self.bpm.store(s.bpm.to_bits(), Ordering::Relaxed);
        self.progress
            .store(s.loop_progress.to_bits(), Ordering::Relaxed);
        self.playing.store(s.playing, Ordering::Relaxed);
        self.active.store(s.active_loop, Ordering::Relaxed);
        self.mode.store(s.mode, Ordering::Relaxed);
        self.external.store(s.external_clock, Ordering::Relaxed);
        self.clock.store(s.clock_state, Ordering::Relaxed);
        self.pending.store(s.pending, Ordering::Relaxed);
        for i in 0..s.queue_count as usize {
            self.queue[i].store(s.queue[i], Ordering::Relaxed);
        }
        self.count.store(s.queue_count, Ordering::Release);
        self.step.store(s.active_step, Ordering::Relaxed);
        for i in 0..s.active_count as usize {
            self.loops[i].store(s.active_loops[i], Ordering::Relaxed);
            self.tokens[i].store(s.active_tokens[i], Ordering::Relaxed);
            self.active_progress[i].store(s.active_progress[i].to_bits(), Ordering::Relaxed);
        }
        self.active_count.store(s.active_count, Ordering::Release);
        self.version.fetch_add(1, Ordering::Release);
    }
    fn get(&self) -> Snapshot {
        loop {
            let version = self.version.load(Ordering::Acquire);
            if version & 1 != 0 {
                std::hint::spin_loop();
                continue;
            }
            let mut s = Snapshot {
                beat: f64::from_bits(self.beat.load(Ordering::Relaxed)),
                bpm: f64::from_bits(self.bpm.load(Ordering::Relaxed)),
                loop_progress: f64::from_bits(self.progress.load(Ordering::Relaxed)),
                playing: self.playing.load(Ordering::Relaxed),
                active_loop: self.active.load(Ordering::Relaxed),
                mode: self.mode.load(Ordering::Relaxed),
                external_clock: self.external.load(Ordering::Relaxed),
                clock_state: self.clock.load(Ordering::Relaxed),
                pending: self.pending.load(Ordering::Relaxed),
                queue_count: self
                    .count
                    .load(Ordering::Acquire)
                    .clamp(0, MAX_QUEUE as i32),
                active_count: self
                    .active_count
                    .load(Ordering::Acquire)
                    .clamp(0, MAX_LAYERS as i32),
                active_step: self.step.load(Ordering::Relaxed),
                ..Snapshot::default()
            };
            for i in 0..s.queue_count as usize {
                s.queue[i] = self.queue[i].load(Ordering::Relaxed);
            }
            for i in 0..s.active_count as usize {
                s.active_loops[i] = self.loops[i].load(Ordering::Relaxed);
                s.active_tokens[i] = self.tokens[i].load(Ordering::Relaxed);
                s.active_progress[i] =
                    f64::from_bits(self.active_progress[i].load(Ordering::Relaxed));
            }
            std::sync::atomic::fence(Ordering::Acquire);
            if self.version.load(Ordering::Relaxed) == version {
                return s;
            }
        }
    }
}
struct Retired {
    ptr: *mut Parts,
    epoch: u64,
}
pub struct Handle {
    core: UnsafeCell<Core>,
    bank: Bank,
    commands: Ring,
    snapshot: AtomicSnapshot,
    completed: AtomicU64,
    retired: UnsafeCell<Vec<Retired>>,
}
// SAFETY: core is exclusively accessed by the render thread; commands have one
// serialized producer; samples are immutable after publication; retired parts
// are managed only by that same producer. Destroy only after both threads stop.
unsafe impl Sync for Handle {}
impl Handle {
    fn new(sr: f64, output_gain: f32) -> Self {
        Self {
            core: UnsafeCell::new(Core::new(sr, output_gain)),
            bank: Bank::new(),
            commands: Ring::new(),
            snapshot: AtomicSnapshot::new(),
            completed: AtomicU64::new(0),
            retired: UnsafeCell::new(Vec::new()),
        }
    }
    fn set_parts(&self, id: i32, next: *mut Parts) {
        let Some(sample) = self.bank.get(id) else {
            if !next.is_null() {
                unsafe {
                    drop(Box::from_raw(next));
                }
            }
            return;
        };
        if !next.is_null() && unsafe { (*next).frames } != sample.frames {
            unsafe {
                drop(Box::from_raw(next));
            }
            return;
        }
        // Sequential consistency ties pointer reads to callback completion:
        // any callback which can observe `old` precedes this exchange.
        let old = sample.parts.swap(next, Ordering::SeqCst);
        let epoch = self.completed.load(Ordering::SeqCst);
        // SAFETY: all installations and reclamation are on the control producer.
        let retired = unsafe { &mut *self.retired.get() };
        if !old.is_null() {
            retired.push(Retired { ptr: old, epoch });
        }
        let mut i = 0;
        while i < retired.len() {
            if epoch > retired[i].epoch {
                let item = retired.swap_remove(i);
                unsafe {
                    drop(Box::from_raw(item.ptr));
                }
            } else {
                i += 1;
            }
        }
    }
}
impl Drop for Handle {
    fn drop(&mut self) {
        for item in self.retired.get_mut().drain(..) {
            unsafe {
                drop(Box::from_raw(item.ptr));
            }
        }
    }
}
unsafe fn handle<'a>(p: *mut Handle) -> Option<&'a Handle> {
    p.as_ref()
}
unsafe fn simple(p: *mut Handle, kind: u8, value: i32, number: f64) {
    if let Some(h) = unsafe { handle(p) } {
        h.commands.push(Command {
            kind,
            value,
            number,
            ..Command::default()
        });
    }
}

#[no_mangle]
pub extern "C" fn bw_create(sr: f64) -> *mut Handle {
    if !sr.is_finite() || !(1000. ..=384000.).contains(&sr) {
        return ptr::null_mut();
    }
    Box::into_raw(Box::new(Handle::new(sr, 0.8)))
}
#[no_mangle]
pub extern "C" fn bw_create_web(sr: f64) -> *mut Handle {
    if !sr.is_finite() || !(1000. ..=384000.).contains(&sr) {
        return ptr::null_mut();
    }
    Box::into_raw(Box::new(Handle::new(sr, 1.)))
}
/// # Safety
/// The handle must be live, uniquely owned, and no audio or control calls may remain in flight.
#[no_mangle]
pub unsafe extern "C" fn bw_destroy(p: *mut Handle) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}
/// # Safety
/// The handle must be live. Each ID is installed at most once. PCM and slices must point to the indicated readable lengths. This may run concurrently with rendering, but not destruction.
#[no_mangle]
pub unsafe extern "C" fn bw_load_loop(
    p: *mut Handle,
    id: i32,
    pcm: *const f32,
    frames: i32,
    beats: i32,
    slices: *const i32,
    count: i32,
) -> i32 {
    let Some(h) = handle(p) else { return 0 };
    if pcm.is_null() || slices.is_null() || frames < 2 || beats < 1 || count < 1 || count > frames {
        return 0;
    }
    let slice = std::slice::from_raw_parts(slices, count as usize);
    if slice[0] != 0
        || slice
            .iter()
            .enumerate()
            .any(|(i, &x)| x < 0 || x >= frames || (i > 0 && x <= slice[i - 1]))
    {
        return 0;
    }
    let input = std::slice::from_raw_parts(pcm, frames as usize * 2);
    let n = frames as usize;
    let mut planar = vec![0.; n * 2];
    for i in 0..n {
        planar[i] = input[i * 2];
        planar[n + i] = input[i * 2 + 1];
    }
    let sample = Sample {
        frames: n,
        beats,
        slices: slice.to_vec(),
        pcm: planar,
        parts: AtomicPtr::new(ptr::null_mut()),
    };
    h.bank.install(id, sample) as i32
}
/// # Safety
/// The handle must be live; calls must come from the one serialized producer. The IDs pointer must contain count readable values.
#[no_mangle]
pub unsafe extern "C" fn bw_queue(p: *mut Handle, ids: *const i32, count: i32) {
    let Some(h) = handle(p) else { return };
    let n = count.clamp(0, MAX_QUEUE as i32) as usize;
    if n > 0 && ids.is_null() {
        return;
    }
    let mut c = Command {
        kind: QUEUE,
        count: n as i32,
        ..Command::default()
    };
    if n > 0 {
        c.ids[..n].copy_from_slice(std::slice::from_raw_parts(ids, n));
    }
    h.commands.push(c)
}
#[derive(Clone, Copy)]
#[repr(C)]
pub struct BasicClip {
    loop_id: i32,
    token: i32,
    step: i32,
    mask: i32,
}

unsafe fn arrange(p: *mut Handle, clips: *const Clip, count: i32, start: bool) {
    let Some(h) = handle(p) else { return };
    let mut n = count.clamp(0, MAX_QUEUE as i32) as usize;
    if clips.is_null() {
        n = 0
    }
    let mut c = Command {
        kind: ARRANGE,
        value: start as i32,
        count: n as i32,
        ..Command::default()
    };
    if n > 0 {
        c.clips[..n].copy_from_slice(std::slice::from_raw_parts(clips, n));
    }
    h.commands.push(c)
}
unsafe fn arrange_basic(p: *mut Handle, clips: *const BasicClip, count: i32, start: bool) {
    let Some(h) = handle(p) else { return };
    let n = if clips.is_null() {
        0
    } else {
        count.clamp(0, MAX_QUEUE as i32) as usize
    };
    let mut c = Command {
        kind: ARRANGE,
        value: start as i32,
        count: n as i32,
        ..Command::default()
    };
    if n > 0 {
        for (out, clip) in c.clips[..n]
            .iter_mut()
            .zip(std::slice::from_raw_parts(clips, n))
        {
            *out = Clip {
                loop_id: clip.loop_id,
                token: clip.token,
                step: clip.step,
                mask: clip.mask,
                filter_type: 0,
                filter_hz: 1200,
            };
        }
    }
    h.commands.push(c)
}
/// # Safety
/// The handle must be live; calls must come from the one serialized producer. The clips pointer must contain count readable clips.
#[no_mangle]
pub unsafe extern "C" fn bw_arrange(p: *mut Handle, clips: *const BasicClip, count: i32) {
    arrange_basic(p, clips, count, true)
}
/// # Safety
/// The handle must be live; calls must come from the one serialized producer. The clips pointer must contain count readable clips.
#[no_mangle]
pub unsafe extern "C" fn bw_edit_arrangement(p: *mut Handle, clips: *const BasicClip, count: i32) {
    arrange_basic(p, clips, count, false)
}
/// # Safety
/// The handle must be live; the clips pointer must contain count readable extended clips.
#[no_mangle]
pub unsafe extern "C" fn bw_arrange_with_filters(p: *mut Handle, clips: *const Clip, count: i32) {
    arrange(p, clips, count, true)
}
/// # Safety
/// The handle must be live; the clips pointer must contain count readable extended clips.
#[no_mangle]
pub unsafe extern "C" fn bw_edit_arrangement_with_filters(
    p: *mut Handle,
    clips: *const Clip,
    count: i32,
) {
    arrange(p, clips, count, false)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_clip_mask(p: *mut Handle, token: i32, mask: i32) {
    if let Some(h) = unsafe { handle(p) } {
        h.commands.push(Command {
            kind: CLIP_MASK,
            value: token,
            count: mask,
            ..Command::default()
        });
    }
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_clip_filter(p: *mut Handle, token: i32, kind: i32, hz: f64) {
    if let Some(h) = handle(p) {
        h.commands.push(Command {
            kind: CLIP_FILTER,
            value: token,
            count: kind,
            number: hz,
            ..Command::default()
        });
    }
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_enable(p: *mut Handle, id: i32, enabled: i32) {
    simple(p, ENABLE, id, enabled as f64)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_tempo(p: *mut Handle, bpm: f64) {
    simple(p, TEMPO, 0, bpm)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_web_tempo(p: *mut Handle, bpm: f64) {
    simple(p, WEB_TEMPO, 0, bpm)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_web_stop(p: *mut Handle) {
    simple(p, WEB_STOP, 0, 0.)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_mode(p: *mut Handle, mode: i32) {
    simple(p, MODE, mode, 0.)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_external(p: *mut Handle, value: i32) {
    simple(p, EXTERNAL, value, 0.)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_transport(p: *mut Handle, value: i32) {
    simple(p, TRANSPORT, value, 0.)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_midi(p: *mut Handle, status: u8, value: i32, time: f64) {
    if let Some(h) = unsafe { handle(p) } {
        if time.is_finite() {
            h.commands.push(Command {
                kind: MIDI,
                value: status as i32,
                count: value,
                time,
                ..Command::default()
            });
        }
    }
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_offset(p: *mut Handle, ms: f64) {
    simple(p, OFFSET, 0, ms)
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_nudge(p: *mut Handle, ms: f64) {
    simple(p, NUDGE, 0, ms)
}
/// # Safety
/// PCM must point to frames * 8 readable floats in part-major interleaved stereo order.
#[no_mangle]
pub unsafe extern "C" fn bw_create_parts(pcm: *const f32, frames: i32) -> *mut Parts {
    if pcm.is_null() || frames < 2 {
        return ptr::null_mut();
    }
    let n = frames as usize;
    let input = std::slice::from_raw_parts(pcm, n * 8);
    let mut out = vec![0.; n * 8];
    for p in 0..4 {
        for i in 0..n {
            out[p * n * 2 + i] = input[p * n * 2 + i * 2];
            out[p * n * 2 + n + i] = input[p * n * 2 + i * 2 + 1];
        }
    }
    Box::into_raw(Box::new(Parts {
        frames: n,
        pcm: out,
    }))
}
/// # Safety
/// The handle must be live and used by the serialized control producer. A non-null parts pointer must be uniquely owned and is consumed even on failure.
#[no_mangle]
pub unsafe extern "C" fn bw_set_parts(p: *mut Handle, id: i32, parts: *mut Parts) {
    if let Some(h) = handle(p) {
        h.set_parts(id, parts)
    } else if !parts.is_null() {
        drop(Box::from_raw(parts));
    }
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_part_mask(p: *mut Handle, id: i32, mask: i32) {
    if let Some(h) = unsafe { handle(p) } {
        h.commands.push(Command {
            kind: PART_MASK,
            value: id,
            count: mask,
            ..Command::default()
        });
    }
}
/// # Safety
/// The handle must be live, and calls must come from its one serialized control producer.
#[no_mangle]
pub unsafe extern "C" fn bw_filter(p: *mut Handle, kind: i32, hz: f64) {
    simple(p, FILTER, kind, hz)
}
/// # Safety
/// The handle must be live and accessed by only one render thread. Both output pointers must name disjoint writable buffers of n floats.
#[no_mangle]
pub unsafe extern "C" fn bw_render(p: *mut Handle, l: *mut f32, r: *mut f32, n: u32, time: f64) {
    let Some(h) = handle(p) else { return };
    if l.is_null() || r.is_null() || n == 0 || !time.is_finite() {
        return;
    }
    let core = &mut *h.core.get();
    for _ in 0..RING_SIZE - 1 {
        match h.commands.pop() {
            Some(c) => core.command(&h.bank, c),
            None => break,
        }
    }
    let left = std::slice::from_raw_parts_mut(l, n as usize);
    let right = std::slice::from_raw_parts_mut(r, n as usize);
    core.render(&h.bank, left, right, time);
    h.snapshot.set(&core.snapshot(&h.bank));
    h.completed.fetch_add(1, Ordering::SeqCst);
}
/// # Safety
/// The handle must be live and out must point to a writable Snapshot.
#[no_mangle]
pub unsafe extern "C" fn bw_snapshot(p: *mut Handle, out: *mut Snapshot) {
    if let (Some(h), Some(s)) = (handle(p), out.as_mut()) {
        *s = h.snapshot.get();
        s.dropped_commands = h.commands.dropped.load(Ordering::Relaxed);
    }
}

// Wasm host staging. Only the worklet thread calls these; an unfinished object
// is not visible to the renderer, and ownership transfers on successful install.
#[no_mangle]
pub extern "C" fn bw_prepare_loop(frames: i32, beats: i32) -> *mut Sample {
    if frames < 2 || beats < 1 {
        return ptr::null_mut();
    }
    let n = frames as usize;
    Box::into_raw(Box::new(Sample {
        frames: n,
        beats,
        slices: vec![0],
        pcm: vec![0.; n * 2],
        parts: AtomicPtr::new(ptr::null_mut()),
    }))
}
/// # Safety
/// The pointer must refer to a live, exclusively owned prepared loop. The returned buffer is valid until installation or discard.
#[no_mangle]
pub unsafe extern "C" fn bw_prepared_loop_pcm(p: *mut Sample) -> *mut f32 {
    p.as_mut().map_or(ptr::null_mut(), |s| s.pcm.as_mut_ptr())
}
/// # Safety
/// The handle and prepared loop must be live. The loop is consumed even on failure. Each ID is installed at most once; publication may race rendering, but not destruction.
#[no_mangle]
pub unsafe extern "C" fn bw_install_loop(p: *mut Handle, id: i32, s: *mut Sample) -> i32 {
    if s.is_null() {
        return 0;
    }
    let sample = *Box::from_raw(s);
    if let Some(h) = handle(p) {
        h.bank.install(id, sample) as i32
    } else {
        0
    }
}
/// # Safety
/// The pointer must be null or a live prepared loop that has not been installed or discarded.
#[no_mangle]
pub unsafe extern "C" fn bw_discard_loop(p: *mut Sample) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}
#[no_mangle]
pub extern "C" fn bw_prepare_parts(frames: i32) -> *mut Parts {
    if frames < 2 {
        return ptr::null_mut();
    }
    let n = frames as usize;
    Box::into_raw(Box::new(Parts {
        frames: n,
        pcm: vec![0.; n * 8],
    }))
}
/// # Safety
/// The pointer must refer to live, exclusively owned prepared parts. The returned buffer is valid until installation or discard.
#[no_mangle]
pub unsafe extern "C" fn bw_prepared_parts_pcm(p: *mut Parts) -> *mut f32 {
    p.as_mut().map_or(ptr::null_mut(), |s| s.pcm.as_mut_ptr())
}
/// # Safety
/// The pointer must be null or live prepared parts that have not been installed or discarded.
#[no_mangle]
pub unsafe extern "C" fn bw_discard_parts(p: *mut Parts) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}
#[no_mangle]
pub extern "C" fn bw_scratch_alloc(doubles: u32) -> *mut f64 {
    let data = vec![0f64; doubles as usize].into_boxed_slice();
    Box::into_raw(data) as *mut f64
}
/// # Safety
/// The pointer must be null or an allocation returned by bw_scratch_alloc with the original length and not already freed.
#[no_mangle]
pub unsafe extern "C" fn bw_scratch_free(p: *mut f64, doubles: u32) {
    if !p.is_null() {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(
            p,
            doubles as usize,
        )));
    }
}
#[no_mangle]
pub extern "C" fn bw_snapshot_size() -> u32 {
    std::mem::size_of::<Snapshot>() as u32
}
#[no_mangle]
pub extern "C" fn bw_snapshot_offset(field: u32) -> u32 {
    use std::mem::offset_of;
    (match field {
        0 => offset_of!(Snapshot, beat),
        1 => offset_of!(Snapshot, bpm),
        2 => offset_of!(Snapshot, loop_progress),
        3 => offset_of!(Snapshot, playing),
        4 => offset_of!(Snapshot, active_loop),
        5 => offset_of!(Snapshot, pending),
        6 => offset_of!(Snapshot, queue_count),
        7 => offset_of!(Snapshot, queue),
        8 => offset_of!(Snapshot, active_count),
        9 => offset_of!(Snapshot, active_step),
        10 => offset_of!(Snapshot, active_loops),
        11 => offset_of!(Snapshot, active_tokens),
        12 => offset_of!(Snapshot, active_progress),
        13 => offset_of!(Snapshot, dropped_commands),
        _ => 0,
    }) as u32
}
#[no_mangle]
pub extern "C" fn bw_max_loops() -> u32 {
    MAX_LOOPS as u32
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::alloc::{GlobalAlloc, Layout, System};
    use std::cell::Cell;
    use std::sync::Arc;

    struct CountingAllocator;
    thread_local! {
        static COUNT_ALLOCATIONS: Cell<bool> = const { Cell::new(false) };
        static ALLOCATIONS: Cell<usize> = const { Cell::new(0) };
    }
    fn count_allocation() {
        let _ = COUNT_ALLOCATIONS.try_with(|enabled| {
            if enabled.get() {
                let _ = ALLOCATIONS.try_with(|count| count.set(count.get() + 1));
            }
        });
    }
    unsafe impl GlobalAlloc for CountingAllocator {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            count_allocation();
            System.alloc(layout)
        }
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            count_allocation();
            System.alloc_zeroed(layout)
        }
        unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
            count_allocation();
            System.realloc(ptr, layout, size)
        }
        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            count_allocation();
            System.dealloc(ptr, layout)
        }
    }
    #[global_allocator]
    static ALLOCATOR: CountingAllocator = CountingAllocator;

    #[test]
    fn command_ring_preserves_order_and_reports_overflow() {
        let ring = Ring::new();
        for n in 0..RING_SIZE {
            ring.push(Command {
                value: n as i32,
                ..Command::default()
            });
        }
        assert_eq!(ring.dropped.load(Ordering::Relaxed), 1);
        for n in 0..RING_SIZE - 1 {
            assert_eq!(ring.pop().unwrap().value, n as i32);
        }
        assert!(ring.pop().is_none());
        ring.push(Command {
            value: 123,
            ..Command::default()
        });
        assert_eq!(ring.pop().unwrap().value, 123);
    }

    #[test]
    fn render_and_command_consumption_do_not_allocate_or_free() {
        unsafe {
            let h = bw_create(48000.);
            let pcm = vec![0.1; 512];
            let slices = [0];
            assert_eq!(
                bw_load_loop(h, 0, pcm.as_ptr(), 256, 4, slices.as_ptr(), 1),
                1
            );
            let clips = [Clip {
                loop_id: 0,
                token: 1,
                step: 0,
                mask: 15,
                filter_type: 0,
                filter_hz: 1200,
            }];
            bw_arrange_with_filters(h, clips.as_ptr(), 1);
            let mut left = [0.; 128];
            let mut right = [0.; 128];
            ALLOCATIONS.with(|count| count.set(0));
            COUNT_ALLOCATIONS.with(|enabled| enabled.set(true));
            for block in 0..200 {
                bw_clip_filter(h, 1, block % 4, 200. + block as f64 * 10.);
                bw_render(
                    h,
                    left.as_mut_ptr(),
                    right.as_mut_ptr(),
                    128,
                    block as f64 * 128. / 48000.,
                );
            }
            COUNT_ALLOCATIONS.with(|enabled| enabled.set(false));
            let allocations = ALLOCATIONS.with(Cell::get);
            bw_destroy(h);
            assert_eq!(allocations, 0);
        }
    }

    #[test]
    fn validates_samples_and_consumes_staged_ownership() {
        unsafe {
            let h = bw_create(48000.);
            let pcm = vec![0.25; 64];
            let invalid = [1, 4];
            assert_eq!(
                bw_load_loop(h, 0, pcm.as_ptr(), 32, 4, invalid.as_ptr(), 2),
                0
            );
            let invalid = [0, 0];
            assert_eq!(
                bw_load_loop(h, 0, pcm.as_ptr(), 32, 4, invalid.as_ptr(), 2),
                0
            );
            let valid = [0, 4];
            assert_eq!(
                bw_load_loop(h, 0, pcm.as_ptr(), 32, 4, valid.as_ptr(), 2),
                1
            );
            assert_eq!(
                bw_load_loop(h, 0, pcm.as_ptr(), 32, 4, valid.as_ptr(), 2),
                0
            );
            let staged = bw_prepare_loop(32, 4);
            assert_eq!(bw_install_loop(h, 0, staged), 0); // consumed even on failure
            let staged = bw_prepare_loop(32, 4);
            assert_eq!(bw_install_loop(h, 1, staged), 1);
            bw_set_parts(h, 1, bw_prepare_parts(31)); // mismatch is consumed
            bw_destroy(h);
        }
    }

    #[test]
    fn loops_can_be_published_while_rendering() {
        unsafe {
            let h = bw_create(48000.);
            let address = h as usize;
            let writer = std::thread::spawn(move || {
                let h = address as *mut Handle;
                let pcm = vec![0.1; 512];
                let slices = [0];
                for id in 0..256 {
                    assert_eq!(
                        bw_load_loop(h, id, pcm.as_ptr(), 256, 4, slices.as_ptr(), 1),
                        1
                    );
                }
            });
            let mut left = [0.; 64];
            let mut right = [0.; 64];
            for block in 0..4000 {
                bw_render(
                    h,
                    left.as_mut_ptr(),
                    right.as_mut_ptr(),
                    64,
                    block as f64 * 64. / 48000.,
                );
                assert!(left
                    .iter()
                    .chain(right.iter())
                    .all(|value| value.is_finite()));
            }
            writer.join().unwrap();
            let ids = [255];
            bw_queue(h, ids.as_ptr(), 1);
            for block in 0..4 {
                bw_render(
                    h,
                    left.as_mut_ptr(),
                    right.as_mut_ptr(),
                    64,
                    6. + block as f64 * 64. / 48000.,
                );
            }
            assert!(left.iter().any(|value| *value != 0.));
            bw_destroy(h);
        }
    }

    #[test]
    fn snapshots_are_coherent_while_render_publishes() {
        let shared = Arc::new(AtomicSnapshot::new());
        let writer = Arc::clone(&shared);
        let thread = std::thread::spawn(move || {
            for value in 1..20_000 {
                let mut snapshot = Snapshot {
                    beat: value as f64,
                    bpm: (value * 2) as f64,
                    active_count: 1,
                    ..Snapshot::default()
                };
                snapshot.active_tokens[0] = value;
                writer.set(&snapshot);
            }
        });
        for _ in 0..20_000 {
            let snapshot = shared.get();
            if snapshot.beat > 0. {
                assert_eq!(snapshot.bpm, snapshot.beat * 2.);
                assert_eq!(snapshot.active_tokens[0], snapshot.beat as i32);
            }
        }
        thread.join().unwrap();
    }

    #[test]
    fn parts_can_be_replaced_while_audio_and_snapshots_run() {
        unsafe {
            let h = bw_create(48000.);
            let pcm = vec![0.1; 512];
            let slices = [0];
            assert_eq!(
                bw_load_loop(h, 3, pcm.as_ptr(), 256, 4, slices.as_ptr(), 1),
                1
            );
            bw_queue(h, [3].as_ptr(), 1);
            let address = h as usize;
            let writer = std::thread::spawn(move || {
                let h = address as *mut Handle;
                let parts = vec![0.02; 256 * 8];
                for i in 0..2500 {
                    bw_set_parts(
                        h,
                        3,
                        if i % 3 == 0 {
                            ptr::null_mut()
                        } else {
                            bw_create_parts(parts.as_ptr(), 256)
                        },
                    );
                    if i % 50 == 0 {
                        bw_part_mask(h, 3, i & 15);
                    }
                }
            });
            let mut left = [0f32; 64];
            let mut right = [0f32; 64];
            for block in 0..4000 {
                bw_render(
                    h,
                    left.as_mut_ptr(),
                    right.as_mut_ptr(),
                    64,
                    block as f64 * 64. / 48000.,
                );
                let mut snapshot = Snapshot::default();
                bw_snapshot(h, &mut snapshot);
                assert!(left.iter().chain(right.iter()).all(|x| x.is_finite()));
                assert!(snapshot.active_count >= 0 && snapshot.active_count <= MAX_LAYERS as i32);
            }
            writer.join().unwrap();
            bw_destroy(h);
        }
    }
}

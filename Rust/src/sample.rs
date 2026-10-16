use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicPtr, Ordering};

pub const MAX_LOOPS: usize = 1024;

pub struct Parts {
    pub frames: usize,
    // Part-major; within each part, left then right planar samples.
    pub pcm: Vec<f32>,
}

pub struct Sample {
    pub frames: usize,
    pub beats: i32,
    pub slices: Vec<i32>,
    // Left then right planar samples.
    pub pcm: Vec<f32>,
    pub parts: AtomicPtr<Parts>,
}
impl Drop for Sample {
    fn drop(&mut self) {
        let p = *self.parts.get_mut();
        if !p.is_null() {
            // SAFETY: destruction happens after the audio thread has stopped.
            unsafe {
                drop(Box::from_raw(p));
            }
        }
    }
}

pub struct Slot(pub UnsafeCell<Option<Sample>>);
// SAFETY: a slot is written once before audio starts, or from the Wasm audio
// thread between callbacks. Published samples are immutable except for parts,
// whose pointer is atomic and whose retired allocations outlive render blocks.
unsafe impl Sync for Slot {}

pub struct Bank(pub Box<[Slot]>);
impl Bank {
    pub fn new() -> Self {
        Self(
            (0..MAX_LOOPS)
                .map(|_| Slot(UnsafeCell::new(None)))
                .collect(),
        )
    }
    pub fn get(&self, id: i32) -> Option<&Sample> {
        if !(0..MAX_LOOPS as i32).contains(&id) {
            return None;
        }
        // SAFETY: see Slot's publication contract above.
        unsafe { (&*self.0[id as usize].0.get()).as_ref() }
    }
    pub unsafe fn install(&self, id: i32, sample: Sample) -> bool {
        if !(0..MAX_LOOPS as i32).contains(&id) {
            return false;
        }
        let slot = &mut *self.0[id as usize].0.get();
        if slot.is_some() {
            return false;
        }
        *slot = Some(sample);
        true
    }
}
impl Sample {
    pub fn parts(&self) -> Option<&Parts> {
        let ptr = self.parts.load(Ordering::SeqCst);
        // SAFETY: pointer publication, callback completion, and pointer reads
        // share a total order. Reclamation waits for a callback to complete
        // after the exchange, so every callback that could observe the retired
        // pointer has finished before its storage is freed.
        unsafe { ptr.as_ref() }
    }
}

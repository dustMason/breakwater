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

// A loop is installed at most once and stays alive until the bank is dropped.
pub struct Bank(pub Box<[AtomicPtr<Sample>]>);
impl Bank {
    pub fn new() -> Self {
        Self(
            (0..MAX_LOOPS)
                .map(|_| AtomicPtr::new(std::ptr::null_mut()))
                .collect(),
        )
    }
    pub fn get(&self, id: i32) -> Option<&Sample> {
        if !(0..MAX_LOOPS as i32).contains(&id) {
            return None;
        }
        // SAFETY: published samples remain alive for the lifetime of the bank.
        unsafe { self.0[id as usize].load(Ordering::Acquire).as_ref() }
    }
    pub fn install(&self, id: i32, sample: Sample) -> bool {
        if !(0..MAX_LOOPS as i32).contains(&id) {
            return false;
        }
        let raw = Box::into_raw(Box::new(sample));
        if self.0[id as usize]
            .compare_exchange(
                std::ptr::null_mut(),
                raw,
                Ordering::Release,
                Ordering::Relaxed,
            )
            .is_err()
        {
            // The rejected object was never published and remains ours.
            unsafe {
                drop(Box::from_raw(raw));
            }
            return false;
        }
        true
    }
}
impl Drop for Bank {
    fn drop(&mut self) {
        for slot in self.0.iter_mut() {
            let sample = *slot.get_mut();
            if !sample.is_null() {
                // SAFETY: the owner stops all access before dropping the bank.
                unsafe {
                    drop(Box::from_raw(sample));
                }
            }
        }
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

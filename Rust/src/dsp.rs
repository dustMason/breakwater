use crate::sample::{Bank, Sample};

#[derive(Clone, Copy, Default)]
pub struct Stereo {
    pub l: f32,
    pub r: f32,
}
impl Stereo {
    fn scale(self, a: f64) -> Self {
        Self {
            l: (self.l as f64 * a) as f32,
            r: (self.r as f64 * a) as f32,
        }
    }
    fn add(self, b: Self) -> Self {
        Self {
            l: self.l + b.l,
            r: self.r + b.r,
        }
    }
}
#[derive(Clone, Copy)]
pub struct Voice {
    pub id: i32,
    pub token: i32,
    mode: i32,
    slice: i32,
    previous_slice: i32,
    position: f64,
    old_position: f64,
    pub local_beat: f64,
    fade: i32,
    mask: i32,
    gains: [f32; 4],
    blend: f32,
    audible: f32,
    level: f32,
    target_level: f32,
    last: Stereo,
    wrap_tail: Stereo,
    wrap_fade: i32,
    filter: Filter,
}
impl Default for Voice {
    fn default() -> Self {
        Self {
            id: -1,
            token: 0,
            mode: 0,
            slice: -1,
            previous_slice: -1,
            position: 0.,
            old_position: 0.,
            local_beat: 0.,
            fade: 0,
            mask: 15,
            gains: [1.; 4],
            blend: 0.,
            audible: 1.,
            level: 1.,
            target_level: 1.,
            last: Stereo::default(),
            wrap_tail: Stereo::default(),
            wrap_fade: 0,
            filter: Filter::new(48000.),
        }
    }
}
impl Voice {
    pub fn prepare_filter(&mut self, sr: f64, kind: i32, hz: f64) {
        self.filter = Filter::new(sr);
        self.filter.set(kind, hz);
    }
    pub fn set_filter(&mut self, kind: i32, hz: f64) {
        self.filter.set(kind, hz);
    }
    pub fn filter_sample(&mut self, sample: Stereo) -> Stereo {
        self.filter.process(sample).scale(self.level as f64)
    }
    pub fn set_level(&mut self, level: f32, immediate: bool) {
        self.target_level = level.clamp(0., 1.);
        if immediate {
            self.level = self.target_level;
        }
    }
    pub fn mask(&mut self, m: i32, immediate: bool) {
        self.mask = m & 15;
        if immediate {
            for p in 0..4 {
                self.gains[p] = if self.mask & (1 << p) != 0 { 1. } else { 0. };
            }
            self.audible = if self.mask != 0 { 1. } else { 0. };
        }
    }
    pub fn advance_parts(&mut self, bank: &Bank, sr: f64) {
        let Some(s) = bank.get(self.id) else { return };
        let step = (1. / (sr * 0.008)) as f32;
        self.level += (self.target_level - self.level).clamp(-step, step);
        for p in 0..4 {
            let wanted = if self.mask & (1 << p) != 0 { 1. } else { 0. };
            self.gains[p] += (wanted - self.gains[p]).clamp(-step, step);
        }
        let wanted = if s.parts().is_some() { 1. } else { 0. };
        self.blend += (wanted - self.blend).clamp(-step, step);
        let wanted = if self.mask != 0 { 1. } else { 0. };
        self.audible += (wanted - self.audible).clamp(-step, step);
    }
    fn at(&self, s: &Sample, index: f64) -> Stereo {
        let index = index.clamp(0., (s.frames - 1) as f64);
        let a = index as usize;
        let b = (a + 1).min(s.frames - 1);
        let f = index - a as f64;
        let interp = |base: usize| -> f32 {
            (s.pcm[base + a] as f64 * (1. - f) + s.pcm[base + b] as f64 * f) as f32
        };
        let mut out = Stereo {
            l: interp(0),
            r: interp(s.frames),
        };
        if let Some(parts) = s.parts() {
            let sum: f32 = self.gains.iter().sum();
            // Neural estimates need not reconstruct the mix. Partial masks sum
            // the selected stems; only all four enabled restores the original.
            let original = (sum - 3.).clamp(0., 1.);
            out = out.scale((1. - self.blend + self.blend * original) as f64);
            for p in 0..4 {
                let amount = (self.gains[p] - original) * self.blend;
                if amount == 0. {
                    continue;
                }
                let base = p * s.frames * 2;
                let value = |off: usize| -> f32 {
                    (parts.pcm[base + off + a] as f64 * (1. - f)
                        + parts.pcm[base + off + b] as f64 * f) as f32
                };
                out.l += amount * value(0);
                out.r += amount * value(s.frames);
            }
        }
        out.scale(self.audible as f64)
    }
    fn slice_at(&self, s: &Sample, index: i32, elapsed: f64, sr: f64) -> Stereo {
        if index < 0 {
            return Stereo::default();
        };
        let i = index as usize;
        let start = s.slices[i] as usize;
        let end = if i + 1 < s.slices.len() {
            s.slices[i + 1] as usize
        } else {
            s.frames
        };
        let length = end - start;
        if length <= 1 {
            return Stereo::default();
        };
        if elapsed < (length as f64) {
            return self.at(s, start as f64 + elapsed);
        }
        let grain = ((sr * 0.035) as usize).min(length / 2);
        let blend = ((sr * 0.004) as usize).min(grain / 4);
        if grain < 16 || blend == 0 {
            return Stereo::default();
        }
        let tail = elapsed - length as f64;
        let phase = tail % ((grain - blend) as f64);
        let mut result = self.at(s, (end - grain) as f64 + phase);
        if phase < (blend as f64) {
            let f = phase / blend as f64;
            result = self
                .at(s, (end - blend) as f64 + phase)
                .scale(1. - f)
                .add(result.scale(f));
        }
        result.scale((-tail / (sr * 0.075)).exp())
    }
    pub fn begin(&mut self, bank: &Bank, id: i32, mode: i32, phase: f64) {
        self.id = id;
        self.mode = mode;
        self.local_beat = phase;
        self.slice = -1;
        self.previous_slice = -1;
        self.fade = 0;
        self.wrap_fade = 0;
        let Some(s) = bank.get(id) else {
            self.id = -1;
            return;
        };
        self.position = phase / s.beats as f64 * s.frames as f64;
        if mode == 1 {
            for (i, x) in s.slices.iter().enumerate() {
                if (*x as f64) / s.frames as f64 * s.beats as f64 <= phase {
                    self.slice = i as i32;
                }
            }
            if self.slice < 0 {
                self.slice = 0
            };
            self.position =
                phase / s.beats as f64 * s.frames as f64 - s.slices[self.slice as usize] as f64;
        }
    }
    pub fn render(&mut self, bank: &Bank, phase: f64, _delta: f64, sr: f64) -> Stereo {
        let Some(s) = bank.get(self.id) else {
            return Stereo::default();
        };
        self.local_beat = phase;
        if self.mode == 0 {
            return self.at(s, phase / s.beats as f64 * s.frames as f64);
        }
        let mut wanted = self.slice;
        while (wanted + 1) < s.slices.len() as i32
            && s.slices[(wanted + 1) as usize] as f64 / s.frames as f64 * s.beats as f64
                <= phase + 1e-10
        {
            wanted += 1;
        }
        if wanted != self.slice {
            self.previous_slice = self.slice;
            self.old_position = self.position;
            self.slice = wanted;
            self.position = 0.;
            self.fade = (sr * 0.002) as i32;
        }
        let mut sample = self.slice_at(s, self.slice, self.position, sr);
        self.position += 1.;
        if self.fade > 0 && self.previous_slice >= 0 {
            let f = self.fade as f64 / (sr * 0.002);
            sample = sample.scale(1. - f).add(
                self.slice_at(s, self.previous_slice, self.old_position, sr)
                    .scale(f),
            );
            self.old_position += 1.;
            self.fade -= 1;
        }
        sample
    }
    pub fn tail(&mut self, bank: &Bank, delta: f64, sr: f64) -> Stereo {
        self.local_beat += delta;
        self.render(bank, self.local_beat, delta, sr)
    }
    pub fn wrapped(&mut self, bank: &Bank, phase: f64, delta: f64, sr: f64) -> Stereo {
        if self.id >= 0 && phase + 1e-7 < self.local_beat {
            self.wrap_tail = self.last;
            self.begin(bank, self.id, self.mode, phase);
            self.wrap_fade = (sr * 0.005) as i32;
        }
        let mut result = self.render(bank, phase, delta, sr);
        if self.wrap_fade > 0 {
            let f = self.wrap_fade as f64 / (sr * 0.005);
            result = result.scale(1. - f).add(self.wrap_tail.scale(f));
            self.wrap_fade -= 1;
        }
        self.last = result;
        result
    }
}

#[derive(Clone, Copy)]
pub struct Filter {
    sr: f64,
    slew: f64,
    kind: i32,
    current: [f64; 5],
    target: [f64; 5],
    z1: [f64; 2],
    z2: [f64; 2],
    mix: f64,
}
impl Filter {
    pub fn new(sr: f64) -> Self {
        Self {
            sr,
            slew: 1. - (-1. / (sr * 0.012)).exp(),
            kind: 0,
            current: [1., 0., 0., 0., 0.],
            target: [1., 0., 0., 0., 0.],
            z1: [0.; 2],
            z2: [0.; 2],
            mix: 0.,
        }
    }
    pub fn set(&mut self, kind: i32, hz: f64) {
        self.kind = kind.clamp(0, 3);
        if self.kind == 0 {
            return;
        };
        let cutoff = hz.clamp(20., self.sr * 0.45);
        let omega = 2. * std::f64::consts::PI * cutoff / self.sr;
        let c = omega.cos();
        let a = omega.sin() / (2. * std::f64::consts::FRAC_1_SQRT_2);
        let d = 1. + a;
        self.target = match self.kind {
            1 => [
                (1. - c) / (2. * d),
                (1. - c) / d,
                (1. - c) / (2. * d),
                -2. * c / d,
                (1. - a) / d,
            ],
            2 => [a / d, 0., -a / d, -2. * c / d, (1. - a) / d],
            _ => [
                (1. + c) / (2. * d),
                -(1. + c) / d,
                (1. + c) / (2. * d),
                -2. * c / d,
                (1. - a) / d,
            ],
        };
    }
    pub fn process(&mut self, input: Stereo) -> Stereo {
        for i in 0..5 {
            self.current[i] += (self.target[i] - self.current[i]) * self.slew;
        }
        self.mix += ((if self.kind != 0 { 1. } else { 0. }) - self.mix) * self.slew;
        let input = [input.l as f64, input.r as f64];
        let mut out = [0.; 2];
        for i in 0..2 {
            let y = self.current[0] * input[i] + self.z1[i];
            self.z1[i] = self.current[1] * input[i] - self.current[3] * y + self.z2[i];
            self.z2[i] = self.current[2] * input[i] - self.current[4] * y;
            out[i] = input[i] + self.mix * (y - input[i]);
        }
        Stereo {
            l: out[0] as f32,
            r: out[1] as f32,
        }
    }
}

use crate::dsp::{Filter, MasterDynamics, Stereo, Voice};
use crate::sample::{Bank, MAX_LOOPS};

pub const MAX_QUEUE: usize = 64;
pub const MAX_LAYERS: usize = 16;
const MAX_SIDE_LAYERS: usize = 8;
#[derive(Clone, Copy, Default, Debug)]
#[repr(C)]
pub struct Clip {
    pub loop_id: i32,
    pub token: i32,
    pub step: i32,
    pub mask: i32,
    pub filter_type: i32,
    pub filter_hz: i32,
    pub level_milli: i32,
}
#[derive(Clone, Copy)]
pub struct Command {
    pub kind: u8,
    pub value: i32,
    pub count: i32,
    pub number: f64,
    pub time: f64,
    pub ids: [i32; MAX_QUEUE],
    pub clips: [Clip; MAX_QUEUE],
}
impl Default for Command {
    fn default() -> Self {
        Self {
            kind: 0,
            value: 0,
            count: 0,
            number: 0.,
            time: 0.,
            ids: [0; MAX_QUEUE],
            clips: [Clip::default(); MAX_QUEUE],
        }
    }
}
pub const QUEUE: u8 = 0;
pub const ARRANGE: u8 = 1;
pub const ENABLE: u8 = 2;
pub const TEMPO: u8 = 3;
pub const MODE: u8 = 4;
pub const EXTERNAL: u8 = 5;
pub const TRANSPORT: u8 = 6;
pub const MIDI: u8 = 7;
pub const OFFSET: u8 = 8;
pub const NUDGE: u8 = 9;
pub const PART_MASK: u8 = 10;
pub const CLIP_MASK: u8 = 11;
pub const FILTER: u8 = 12;
pub const WEB_STOP: u8 = 13;
pub const WEB_TEMPO: u8 = 14;
pub const CLIP_FILTER: u8 = 15;
pub const CLIP_LEVEL: u8 = 16;
pub const STACKS: u8 = 17;
pub const CROSSFADE: u8 = 18;

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Snapshot {
    pub beat: f64,
    pub bpm: f64,
    pub loop_progress: f64,
    pub playing: i32,
    pub active_loop: i32,
    pub mode: i32,
    pub external_clock: i32,
    pub clock_state: i32,
    pub pending: i32,
    pub queue_count: i32,
    pub queue: [i32; MAX_QUEUE],
    pub active_count: i32,
    pub active_step: i32,
    pub active_loops: [i32; MAX_LAYERS],
    pub active_tokens: [i32; MAX_LAYERS],
    pub active_progress: [f64; MAX_LAYERS],
    pub dropped_commands: u32,
}
impl Default for Snapshot {
    fn default() -> Self {
        Self {
            beat: 0.,
            bpm: 120.,
            loop_progress: 0.,
            playing: 0,
            active_loop: -1,
            mode: 0,
            external_clock: 0,
            clock_state: 0,
            pending: 0,
            queue_count: 0,
            queue: [0; MAX_QUEUE],
            active_count: 0,
            active_step: 0,
            active_loops: [0; MAX_LAYERS],
            active_tokens: [0; MAX_LAYERS],
            active_progress: [0.; MAX_LAYERS],
            dropped_commands: 0,
        }
    }
}

pub struct Core {
    sr: f64,
    beat: f64,
    bpm: f64,
    target_bpm: f64,
    clock_bpm: f64,
    offset: f64,
    nudge_offset: f64,
    nudge_remaining: f64,
    enabled: [bool; MAX_LOOPS],
    masks: [i32; MAX_LOOPS],
    cycle: [i32; MAX_QUEUE],
    pending_ids: [i32; MAX_QUEUE],
    cycle_count: usize,
    cycle_pos: usize,
    pending_count: usize,
    pending: bool,
    running: bool,
    external: bool,
    have_tick: bool,
    transport_clock: bool,
    arrangement: [Clip; MAX_QUEUE],
    pending_arrangement: [Clip; MAX_QUEUE],
    arrangement_count: usize,
    pending_arrangement_count: usize,
    arranged: bool,
    stacks: bool,
    pending_stacks: bool,
    crossfade: f64,
    crossfade_target: f64,
    side_gain: [f64; 2],
    arrangement_pending: bool,
    arrangement_step: i32,
    step_beats: i32,
    layer_count: usize,
    old_layer_count: usize,
    layer_transition: i32,
    layers: [Voice; MAX_LAYERS],
    old_layers: [Voice; MAX_LAYERS],
    active: i32,
    mode: i32,
    clock_state: i32,
    interval_count: usize,
    interval_index: usize,
    start_beat: f64,
    next_bar: f64,
    last_tick: f64,
    clock_pulse: f64,
    intervals: [f64; 12],
    voice: Voice,
    outgoing: Voice,
    transition: i32,
    gain: f32,
    output_gain: f32,
    web_rewind: bool,
    filter: Filter,
    dynamics: MasterDynamics,
}
impl Core {
    pub fn new(sr: f64, output_gain: f32) -> Self {
        Self {
            sr,
            beat: 0.,
            bpm: 120.,
            target_bpm: 120.,
            clock_bpm: 120.,
            offset: 0.,
            nudge_offset: 0.,
            nudge_remaining: 0.,
            enabled: [true; MAX_LOOPS],
            masks: [15; MAX_LOOPS],
            cycle: [0; MAX_QUEUE],
            pending_ids: [0; MAX_QUEUE],
            cycle_count: 0,
            cycle_pos: 0,
            pending_count: 0,
            pending: false,
            running: false,
            external: false,
            have_tick: false,
            transport_clock: false,
            arrangement: [Clip::default(); MAX_QUEUE],
            pending_arrangement: [Clip::default(); MAX_QUEUE],
            arrangement_count: 0,
            pending_arrangement_count: 0,
            arranged: false,
            stacks: false,
            pending_stacks: false,
            crossfade: 0.,
            crossfade_target: 0.,
            side_gain: [1., 0.],
            arrangement_pending: false,
            arrangement_step: 0,
            step_beats: 4,
            layer_count: 0,
            old_layer_count: 0,
            layer_transition: 0,
            layers: [Voice::default(); MAX_LAYERS],
            old_layers: [Voice::default(); MAX_LAYERS],
            active: -1,
            mode: 0,
            clock_state: 0,
            interval_count: 0,
            interval_index: 0,
            start_beat: 0.,
            next_bar: 4.,
            last_tick: -1.,
            clock_pulse: -1.,
            intervals: [0.; 12],
            voice: Voice::default(),
            outgoing: Voice::default(),
            transition: 0,
            gain: 0.,
            output_gain,
            web_rewind: false,
            filter: Filter::new(sr),
            dynamics: MasterDynamics::new(sr),
        }
    }
    fn valid(&self, b: &Bank, id: i32) -> bool {
        id >= 0 && (id as usize) < MAX_LOOPS && self.enabled[id as usize] && b.get(id).is_some()
    }
    fn beats(b: &Bank, id: i32) -> i32 {
        b.get(id).map_or(4, |s| s.beats)
    }
    fn launch(&mut self, b: &Bank, id: i32, at: f64) {
        self.outgoing = self.voice;
        self.transition = (self.sr * 0.005) as i32;
        self.active = id;
        self.start_beat = at;
        let valid = self.valid(b, id);
        self.voice
            .begin(b, if valid { id } else { -1 }, self.mode, 0.);
        self.voice.token = id;
        self.voice
            .mask(if valid { self.masks[id as usize] } else { 15 }, true);
    }
    fn next_step(&self, b: &Bank, current: i32) -> i32 {
        let mut first = MAX_QUEUE as i32;
        let mut next = MAX_QUEUE as i32;
        for c in &self.arrangement[..self.arrangement_count] {
            if self.valid(b, c.loop_id) {
                first = first.min(c.step);
                if c.step > current {
                    next = next.min(c.step);
                }
            }
        }
        if next < MAX_QUEUE as i32 {
            next
        } else if first < MAX_QUEUE as i32 {
            first
        } else {
            -1
        }
    }
    fn launch_step(&mut self, b: &Bank, step: i32, at: f64, phase: f64) {
        if self.stacks {
            self.launch_stacks(b, at, false, phase);
            return;
        }
        if self.arranged {
            self.old_layers = self.layers;
            self.old_layer_count = self.layer_count;
        } else {
            self.old_layers[0] = self.voice;
            self.old_layer_count = usize::from(self.voice.id >= 0);
        }
        self.layer_transition = (self.sr * 0.005) as i32;
        self.layer_count = 0;
        self.step_beats = 1;
        self.arrangement_step = step;
        self.start_beat = at;
        for i in 0..self.arrangement_count {
            if self.layer_count >= MAX_LAYERS {
                break;
            }
            let c = self.arrangement[i];
            if c.step != step || !self.valid(b, c.loop_id) {
                continue;
            }
            let mut v = Voice::default();
            v.token = c.token;
            v.mask(c.mask, true);
            v.prepare_filter(self.sr, c.filter_type, c.filter_hz as f64);
            v.set_level(c.level_milli as f32 / 1000., true);
            v.begin(
                b,
                c.loop_id,
                self.mode,
                phase.max(0.) % Self::beats(b, c.loop_id) as f64,
            );
            self.layers[self.layer_count] = v;
            self.layer_count += 1;
            self.step_beats = self.step_beats.max(Self::beats(b, c.loop_id));
        }
        self.active = -1;
        for c in &self.arrangement[..self.arrangement_count] {
            if c.step == step && self.valid(b, c.loop_id) {
                self.active = c.loop_id;
                break;
            }
        }
    }
    // Replace the stack membership on a bar boundary while preserving the
    // phase and filter state of every retained clip. New clips start at beat 1.
    fn launch_stacks(&mut self, b: &Bank, at: f64, preserve: bool, phase: f64) {
        self.old_layers = self.layers;
        self.old_layer_count = if self.arranged { self.layer_count } else { 0 };
        self.layer_transition = (self.sr * 0.005) as i32;
        self.layer_count = 0;
        self.step_beats = 4;
        self.start_beat = at;
        self.arrangement_step = 0;
        self.active = -1;
        for c in &self.arrangement[..self.arrangement_count] {
            if !self.valid(b, c.loop_id) || self.layer_count >= MAX_LAYERS {
                continue;
            }
            let retained = if preserve {
                self.old_layers[..self.old_layer_count]
                    .iter()
                    .find(|v| v.token == c.token && v.id == c.loop_id)
                    .copied()
            } else {
                None
            };
            let mut v = if let Some(v) = retained {
                v
            } else {
                let mut v = Voice::default();
                v.token = c.token;
                v.start_beat = at;
                v.mask(c.mask, true);
                v.prepare_filter(self.sr, c.filter_type, c.filter_hz as f64);
                v.set_level(c.level_milli as f32 / 1000., true);
                v.begin(
                    b,
                    c.loop_id,
                    self.mode,
                    phase.max(0.) % Self::beats(b, c.loop_id) as f64,
                );
                v
            };
            v.side = c.step as usize;
            v.mask(c.mask, false);
            v.set_filter(c.filter_type, c.filter_hz as f64);
            v.set_level(c.level_milli as f32 / 1000., false);
            self.layers[self.layer_count] = v;
            self.layer_count += 1;
            if self.active < 0 {
                self.active = c.loop_id;
            }
        }
    }
    fn rephase_stacks(&mut self, b: &Bank) {
        self.old_layers = self.layers;
        self.old_layer_count = self.layer_count;
        self.layer_transition = (self.sr * 0.005) as i32;
        for voice in &mut self.layers[..self.layer_count] {
            let phase = (self.beat - voice.start_beat).rem_euclid(Self::beats(b, voice.id) as f64);
            voice.start_beat = self.beat - phase;
            voice.begin(b, voice.id, self.mode, phase);
        }
    }
    fn apply_arrangement(&mut self, b: &Bank, at: f64, preserve_existing: bool) {
        let was_stacks = self.stacks;
        self.stacks = self.pending_stacks;
        self.arrangement_count = self.pending_arrangement_count;
        self.arrangement[..self.arrangement_count]
            .copy_from_slice(&self.pending_arrangement[..self.arrangement_count]);
        self.arrangement_pending = false;
        self.pending = false;
        if self.stacks {
            self.launch_stacks(b, at, preserve_existing && was_stacks, 0.);
            self.arranged = true;
            if self.layer_count == 0 && !self.external {
                self.running = false;
            }
            return;
        }
        let mut step = -1;
        for c in &self.arrangement[..self.arrangement_count] {
            if self.valid(b, c.loop_id) && (step < 0 || c.step < step) {
                step = c.step;
            }
        }
        let mut found = false;
        if self.arranged {
            for v in 0..self.layer_count {
                for c in &self.arrangement[..self.arrangement_count] {
                    if c.token == self.layers[v].token && self.valid(b, c.loop_id) {
                        step = c.step;
                        found = true;
                        break;
                    }
                }
                if found {
                    break;
                }
            }
        }
        if self.running && found {
            let mut count = 0;
            let mut same = true;
            for i in 0..self.arrangement_count {
                let c = self.arrangement[i];
                if c.step == step && self.valid(b, c.loop_id) {
                    count += 1;
                    let mut matches = false;
                    for v in 0..self.layer_count {
                        if self.layers[v].token == c.token && self.layers[v].id == c.loop_id {
                            self.layers[v].mask(c.mask, false);
                            self.layers[v].set_filter(c.filter_type, c.filter_hz as f64);
                            self.layers[v].set_level(c.level_milli as f32 / 1000., false);
                            matches = true;
                            break;
                        }
                    }
                    if !matches {
                        same = false;
                    }
                }
            }
            if same && count == self.layer_count {
                self.arrangement_step = step;
                return;
            }
        }
        if step >= 0 {
            self.launch_step(b, step, at, 0.);
            self.arranged = true;
        } else {
            self.launch_step(b, -1, at, 0.);
            self.arranged = true;
            if !self.external {
                self.running = false;
            }
        }
    }
    fn apply_pending(&mut self, b: &Bank, at: f64) {
        self.stacks = false;
        self.cycle_count = 0;
        for i in 0..self.pending_count {
            let id = self.pending_ids[i];
            if self.valid(b, id) {
                self.cycle[self.cycle_count] = id;
                self.cycle_count += 1;
            }
        }
        self.cycle_pos = 0;
        self.pending = false;
        if self.arranged && self.layer_count > 0 {
            self.voice = self.layers[0];
            self.arranged = false;
        }
        if self.cycle_count > 0 {
            self.launch(b, self.cycle[0], at)
        } else {
            self.running = false;
            self.active = -1;
        }
    }
    fn clean_queue(&mut self, b: &Bank) {
        let mut count = 0;
        for i in 0..self.cycle_count {
            let id = self.cycle[i];
            if self.valid(b, id) {
                self.cycle[count] = id;
                count += 1;
            }
        }
        self.cycle_count = count;
        self.cycle_pos = 0;
        for i in 0..count {
            if self.cycle[i] == self.active {
                self.cycle_pos = i;
            }
        }
        count = 0;
        for i in 0..self.pending_count {
            let id = self.pending_ids[i];
            if self.valid(b, id) {
                self.pending_ids[count] = id;
                count += 1;
            }
        }
        self.pending_count = count;
        if self.pending && count == 0 && self.valid(b, self.active) {
            self.pending = false;
        }
        if self.active >= 0 && !self.valid(b, self.active) && !self.pending {
            self.pending = true;
            self.pending_count = self.cycle_count;
            self.pending_ids[..self.cycle_count].copy_from_slice(&self.cycle[..self.cycle_count]);
        }
    }
    fn start(&mut self, b: &Bank, reset: bool) {
        if reset {
            self.beat = 0.;
            self.next_bar = 4.;
            self.start_beat = 0.;
            self.clock_pulse = -1.;
        }
        if self.arrangement_pending {
            self.apply_arrangement(b, self.beat, !reset);
            if self.stacks && !reset {
                self.rephase_stacks(b);
            }
        } else if self.pending {
            self.apply_pending(b, self.beat)
        } else if self.arranged && self.arrangement_count > 0 && self.stacks && !reset {
            self.rephase_stacks(b);
        } else if self.arranged && self.arrangement_count > 0 {
            let step = if reset {
                self.next_step(b, -1)
            } else {
                self.arrangement_step
            };
            let phase = if reset {
                0.
            } else {
                (self.beat - self.start_beat).max(0.)
            };
            self.launch_step(
                b,
                step,
                if reset { self.beat } else { self.start_beat },
                phase,
            )
        } else if !reset && self.valid(b, self.active) {
            self.outgoing = self.voice;
            self.transition = (self.sr * 0.005) as i32;
            self.voice.begin(
                b,
                self.active,
                self.mode,
                (self.beat - self.start_beat).max(0.),
            );
        } else if self.cycle_count > 0 {
            self.cycle_pos = 0;
            self.launch(b, self.cycle[0], self.beat)
        } else if self.valid(b, self.active) {
            self.launch(b, self.active, self.beat)
        }
        self.running = true;
        self.transport_clock = true;
    }
    fn midi(&mut self, b: &Bank, status: i32, value: i32, time: f64) {
        if !self.external {
            return;
        }
        match status {
            0xf8 => {
                if self.last_tick >= 0. {
                    let dt = time - self.last_tick;
                    if dt > 0.005 && dt < 0.15 {
                        self.intervals[self.interval_index % 12] = dt;
                        self.interval_index += 1;
                        self.interval_count = (self.interval_count + 1).min(12);
                        let total: f64 = self.intervals[..self.interval_count].iter().sum();
                        self.clock_bpm =
                            (60. * self.interval_count as f64 / (24. * total)).clamp(30., 300.);
                        self.target_bpm = self.clock_bpm;
                    }
                }
                self.last_tick = time;
                self.have_tick = true;
                if self.transport_clock {
                    self.clock_pulse += 1.;
                }
                self.clock_state = if self.interval_count >= 3 { 2 } else { 1 };
            }
            0xfa => {
                self.start(b, true);
                self.last_tick = time;
                self.have_tick = true;
                self.interval_count = 0;
                self.interval_index = 0;
                self.clock_state = 1;
            }
            0xfc => {
                self.running = false;
                self.transport_clock = false;
            }
            0xfb => {
                self.clock_pulse =
                    ((self.beat - (self.offset + self.nudge_offset) * self.clock_bpm / 60.) * 24.)
                        .round()
                        - 1.;
                self.start(b, false);
                self.last_tick = time;
                self.have_tick = true;
            }
            0xf2 => {
                self.beat = value as f64 * 0.25;
                self.clock_pulse = self.beat * 24. - 1.;
                self.next_bar = (self.beat / 4.).floor() * 4. + 4.;
                if self.arranged && self.layer_count > 0 && self.stacks {
                    self.rephase_stacks(b);
                } else if self.arranged && self.layer_count > 0 {
                    self.start_beat =
                        (self.beat / self.step_beats as f64).floor() * self.step_beats as f64;
                    self.launch_step(
                        b,
                        self.arrangement_step,
                        self.start_beat,
                        self.beat - self.start_beat,
                    );
                } else if self.valid(b, self.active) {
                    let beats = Self::beats(b, self.active) as f64;
                    self.start_beat = (self.beat / beats).floor() * beats;
                    self.voice
                        .begin(b, self.active, self.mode, self.beat - self.start_beat);
                } else {
                    self.start_beat = self.beat;
                }
            }
            _ => {}
        }
    }
    pub fn command(&mut self, b: &Bank, c: Command) {
        let was_rewound = self.web_rewind
            && !self.running
            && (c.kind == QUEUE || c.kind == ARRANGE || c.kind == STACKS);
        if was_rewound {
            self.beat = 0.;
            self.next_bar = 4.;
            self.web_rewind = false;
        }
        match c.kind {
            QUEUE => {
                self.pending_count = 0;
                for i in 0..c.count as usize {
                    let id = c.ids[i];
                    if self.valid(b, id) {
                        self.pending_ids[self.pending_count] = id;
                        self.pending_count += 1;
                    }
                }
                if self.pending_count == 0 {
                    return;
                }
                self.pending = true;
                self.arrangement_pending = false;
                if !self.running && !self.external {
                    self.apply_pending(b, self.beat);
                    if self.active >= 0 {
                        self.running = true;
                        self.next_bar = (self.beat / 4.).floor() * 4. + 4.;
                    }
                }
            }
            ARRANGE | STACKS => {
                self.pending_arrangement_count = 0;
                self.pending_stacks = c.kind == STACKS;
                let mut per_step = [0; MAX_QUEUE];
                for i in 0..c.count as usize {
                    let mut clip = c.clips[i];
                    if self.valid(b, clip.loop_id)
                        && clip.step >= 0
                        && (clip.step as usize) < MAX_QUEUE
                        && clip.token > 0
                        && (!self.pending_stacks || clip.step < 2)
                        && per_step[clip.step as usize] < MAX_SIDE_LAYERS
                    {
                        clip.mask &= 15;
                        clip.filter_type = clip.filter_type.clamp(0, 3);
                        clip.filter_hz = clip.filter_hz.clamp(40, 18000);
                        clip.level_milli = clip.level_milli.clamp(0, 1000);
                        self.pending_arrangement[self.pending_arrangement_count] = clip;
                        self.pending_arrangement_count += 1;
                        per_step[clip.step as usize] += 1;
                    }
                }
                self.arrangement_pending = true;
                self.pending = false;
                if c.value != 0 && !self.running && !self.external {
                    self.apply_arrangement(b, self.beat, !was_rewound);
                    if self.active >= 0 {
                        self.running = true;
                        self.next_bar = (self.beat / 4.).floor() * 4. + 4.;
                    }
                }
            }
            CROSSFADE => {
                if c.number.is_finite() {
                    self.crossfade_target = c.number.clamp(0., 1.);
                }
            }
            ENABLE => {
                if c.value >= 0 && (c.value as usize) < MAX_LOOPS {
                    self.enabled[c.value as usize] = c.number != 0.;
                    if (self.arranged || self.arrangement_pending)
                        && !self.enabled[c.value as usize]
                    {
                        if !self.arrangement_pending {
                            self.pending_stacks = self.stacks;
                            self.pending_arrangement_count = self.arrangement_count;
                            self.pending_arrangement[..self.arrangement_count]
                                .copy_from_slice(&self.arrangement[..self.arrangement_count]);
                        }
                        let mut count = 0;
                        for i in 0..self.pending_arrangement_count {
                            let clip = self.pending_arrangement[i];
                            if self.valid(b, clip.loop_id) {
                                self.pending_arrangement[count] = clip;
                                count += 1;
                            }
                        }
                        self.pending_arrangement_count = count;
                        self.arrangement_pending = true;
                    } else if !self.arranged && !self.arrangement_pending {
                        self.clean_queue(b);
                    }
                }
            }
            TEMPO => {
                if !self.external && c.number.is_finite() {
                    self.target_bpm = c.number.clamp(30., 300.);
                }
            }
            MODE => {
                if self.mode != c.value {
                    self.mode = if c.value != 0 { 1 } else { 0 };
                    if self.arranged && self.layer_count > 0 && self.stacks {
                        self.rephase_stacks(b);
                    } else if self.arranged && self.layer_count > 0 {
                        self.launch_step(
                            b,
                            self.arrangement_step,
                            self.start_beat,
                            (self.beat - self.start_beat).max(0.),
                        );
                    } else {
                        self.outgoing = self.voice;
                        self.transition = (self.sr * 0.005) as i32;
                        if self.active >= 0 {
                            self.voice.begin(
                                b,
                                self.active,
                                self.mode,
                                (self.beat - self.start_beat).max(0.),
                            );
                        }
                    }
                }
            }
            EXTERNAL => {
                self.external = c.value != 0;
                self.have_tick = false;
                self.last_tick = -1.;
                self.clock_pulse = -1.;
                self.interval_count = 0;
                self.interval_index = 0;
                self.clock_state = if self.external { 1 } else { 0 };
                self.transport_clock = false;
                self.nudge_offset = 0.;
                self.nudge_remaining = 0.;
                if self.external {
                    self.running = false;
                }
            }
            TRANSPORT => match c.value {
                0 => {
                    self.running = false;
                    self.transport_clock = false;
                }
                1 => self.start(b, true),
                2 => self.start(b, false),
                _ => {
                    self.beat = 0.;
                    self.next_bar = 4.;
                    self.clock_pulse = -1.;
                    self.have_tick = false;
                    if self.arranged && self.layer_count > 0 {
                        self.launch_step(b, self.arrangement_step, 0., 0.)
                    } else if self.active >= 0 {
                        self.launch(b, self.active, 0.)
                    }
                }
            },
            MIDI => self.midi(b, c.value, c.count, c.time),
            OFFSET => {
                if c.number.is_finite() {
                    self.offset = c.number.clamp(-200., 200.) / 1000.;
                }
            }
            NUDGE => {
                if self.running && self.active >= 0 && c.number.is_finite() {
                    let mut step = c.number.clamp(-100., 100.) / 1000.;
                    if self.external {
                        let target = (self.nudge_offset + step).clamp(-2., 2.);
                        step = target - self.nudge_offset;
                        self.nudge_offset = target;
                    }
                    if !self.external
                        || !self.transport_clock
                        || self.clock_state != 2
                        || self.clock_pulse < 0.
                    {
                        self.nudge_remaining += step * self.bpm / 60.;
                    }
                }
            }
            PART_MASK => {
                if c.value >= 0 && (c.value as usize) < MAX_LOOPS {
                    self.masks[c.value as usize] = c.count & 15;
                    if self.voice.id == c.value {
                        self.voice.mask(c.count, false)
                    }
                    if self.outgoing.id == c.value {
                        self.outgoing.mask(c.count, false)
                    }
                }
            }
            CLIP_MASK => {
                for i in 0..self.arrangement_count {
                    if self.arrangement[i].token == c.value {
                        self.arrangement[i].mask = c.count & 15
                    }
                }
                for i in 0..self.pending_arrangement_count {
                    if self.pending_arrangement[i].token == c.value {
                        self.pending_arrangement[i].mask = c.count & 15
                    }
                }
                for i in 0..self.layer_count {
                    if self.layers[i].token == c.value {
                        self.layers[i].mask(c.count, false)
                    }
                }
                for i in 0..self.old_layer_count {
                    if self.old_layers[i].token == c.value {
                        self.old_layers[i].mask(c.count, false)
                    }
                }
            }
            CLIP_FILTER => {
                if c.number.is_finite() {
                    let kind = c.count.clamp(0, 3);
                    let hz = c.number.clamp(40., 18000.);
                    for clip in &mut self.arrangement[..self.arrangement_count] {
                        if clip.token == c.value {
                            clip.filter_type = kind;
                            clip.filter_hz = hz.round() as i32;
                        }
                    }
                    for clip in &mut self.pending_arrangement[..self.pending_arrangement_count] {
                        if clip.token == c.value {
                            clip.filter_type = kind;
                            clip.filter_hz = hz.round() as i32;
                        }
                    }
                    for layer in &mut self.layers[..self.layer_count] {
                        if layer.token == c.value {
                            layer.set_filter(kind, hz);
                        }
                    }
                    for layer in &mut self.old_layers[..self.old_layer_count] {
                        if layer.token == c.value {
                            layer.set_filter(kind, hz);
                        }
                    }
                }
            }
            CLIP_LEVEL => {
                if c.number.is_finite() {
                    let level = c.number.clamp(0., 1.);
                    let milli = (level * 1000.).round() as i32;
                    for clip in &mut self.arrangement[..self.arrangement_count] {
                        if clip.token == c.value {
                            clip.level_milli = milli;
                        }
                    }
                    for clip in &mut self.pending_arrangement[..self.pending_arrangement_count] {
                        if clip.token == c.value {
                            clip.level_milli = milli;
                        }
                    }
                    for layer in &mut self.layers[..self.layer_count] {
                        if layer.token == c.value {
                            layer.set_level(level as f32, false);
                        }
                    }
                    for layer in &mut self.old_layers[..self.old_layer_count] {
                        if layer.token == c.value {
                            layer.set_level(level as f32, false);
                        }
                    }
                }
            }
            FILTER => {
                if c.number.is_finite() {
                    self.filter.set(c.value, c.number)
                }
            }
            WEB_STOP => {
                self.running = false;
                self.transport_clock = false;
                self.pending = false;
                self.arrangement_pending = false;
                self.nudge_remaining = 0.;
                self.web_rewind = true;
            }
            WEB_TEMPO if !self.external && c.number.is_finite() => {
                self.target_bpm = c.number.clamp(30., 300.);
                if !self.running {
                    self.bpm = self.target_bpm;
                }
            }
            _ => {}
        }
    }
    pub fn render(&mut self, b: &Bank, left: &mut [f32], right: &mut [f32], host: f64) {
        let tempo_slew = 1. - (-1. / (self.sr * 0.09)).exp();
        for i in 0..left.len() {
            let previous = self.crossfade;
            self.crossfade += (self.crossfade_target - self.crossfade)
                .clamp(-1. / (self.sr * 0.008), 1. / (self.sr * 0.008));
            if self.crossfade != previous {
                self.side_gain = [
                    (self.crossfade * std::f64::consts::FRAC_PI_2).cos(),
                    (self.crossfade * std::f64::consts::FRAC_PI_2).sin(),
                ];
            }
            let side_gain = self.side_gain;
            let now = host + i as f64 / self.sr;
            self.bpm += (self.target_bpm - self.bpm) * tempo_slew;
            let mut correction = 0.;
            if self.external && self.have_tick {
                let elapsed = (now - self.last_tick).max(0.);
                if elapsed > 2. {
                    self.clock_state = 4;
                    self.running = false;
                    self.transport_clock = false;
                } else if elapsed > 0.25 {
                    self.clock_state = 3;
                } else if self.interval_count >= 3 {
                    self.clock_state = 2;
                }
                if self.running
                    && self.transport_clock
                    && self.clock_state == 2
                    && self.clock_pulse >= 0.
                {
                    let desired = self.clock_pulse / 24.
                        + (elapsed + self.offset + self.nudge_offset) * self.clock_bpm / 60.;
                    let error = desired - self.beat;
                    correction = (error * 60. / 0.12).clamp(-self.bpm * 0.18, self.bpm * 0.18);
                    self.nudge_remaining = 0.;
                }
            }
            if self.running && self.nudge_remaining != 0. {
                let adjust =
                    (self.nudge_remaining * 60. / 0.12).clamp(-self.bpm * 0.18, self.bpm * 0.18);
                let mut applied = adjust / (60. * self.sr);
                if applied.abs() > self.nudge_remaining.abs() {
                    applied = self.nudge_remaining;
                }
                correction += applied * 60. * self.sr;
                self.nudge_remaining -= applied;
            }
            let delta = (self.bpm + correction) / (60. * self.sr);
            if self.running {
                if self.beat + 1e-9 >= self.next_bar {
                    let boundary = self.next_bar;
                    self.next_bar += 4.;
                    if self.arrangement_pending {
                        self.apply_arrangement(b, boundary, true)
                    } else if self.pending {
                        self.apply_pending(b, boundary)
                    }
                }
                if self.arranged
                    && !self.stacks
                    && self.layer_count > 0
                    && self.beat - self.start_beat + 1e-9 >= self.step_beats as f64
                {
                    let boundary = self.start_beat + self.step_beats as f64;
                    self.launch_step(b, self.next_step(b, self.arrangement_step), boundary, 0.)
                } else if !self.arranged
                    && self.active >= 0
                    && self.valid(b, self.active)
                    && self.beat - self.start_beat + 1e-9 >= Self::beats(b, self.active) as f64
                {
                    let boundary = self.start_beat + Self::beats(b, self.active) as f64;
                    if self.cycle_count > 0 {
                        self.cycle_pos = (self.cycle_pos + 1) % self.cycle_count;
                        self.launch(b, self.cycle[self.cycle_pos], boundary)
                    } else {
                        self.launch(b, self.active, boundary)
                    }
                }
            }
            let desired = if self.running && self.active >= 0 {
                1.
            } else {
                0.
            };
            self.gain += ((desired - self.gain as f64)
                .clamp(-1. / (self.sr * 0.008), 1. / (self.sr * 0.003)))
                as f32;
            let mut sample = Stereo::default();
            if self.gain > 0. && self.arranged {
                let mut groups = [Stereo::default(); 2];
                let mut weights_squared = [0.; 2];
                for v in 0..self.layer_count {
                    let layer = &mut self.layers[v];
                    layer.advance_parts(b, self.sr);
                    let phase = (self.beat
                        - if self.stacks {
                            layer.start_beat
                        } else {
                            self.start_beat
                        })
                    .max(0.)
                        % Self::beats(b, layer.id) as f64;
                    let part = if self.running {
                        layer.wrapped(b, phase, delta, self.sr)
                    } else {
                        layer.tail(b, delta, self.sr)
                    };
                    let part = layer.filter_sample(part);
                    let weight = layer.mix_weight();
                    let side = if self.stacks { layer.side } else { 0 };
                    weights_squared[side] += weight * weight;
                    groups[side].l += part.l;
                    groups[side].r += part.r;
                }
                for side in 0..2 {
                    let normalizer = 1. / f64::sqrt(f64::max(1., weights_squared[side]));
                    let gain = normalizer * if self.stacks { side_gain[side] } else { 1. };
                    sample.l += (groups[side].l as f64 * gain) as f32;
                    sample.r += (groups[side].r as f64 * gain) as f32;
                }
                if self.layer_transition > 0 {
                    let mut old = Stereo::default();
                    let mut groups = [Stereo::default(); 2];
                    let mut old_weights_squared = [0.; 2];
                    for v in 0..self.old_layer_count {
                        self.old_layers[v].advance_parts(b, self.sr);
                        let x = self.old_layers[v].tail(b, delta, self.sr);
                        let x = self.old_layers[v].filter_sample(x);
                        let weight = self.old_layers[v].mix_weight();
                        let side = if self.stacks {
                            self.old_layers[v].side
                        } else {
                            0
                        };
                        old_weights_squared[side] += weight * weight;
                        groups[side].l += x.l;
                        groups[side].r += x.r;
                    }
                    for side in 0..2 {
                        let normalizer = 1. / f64::sqrt(f64::max(1., old_weights_squared[side]));
                        let gain = normalizer * if self.stacks { side_gain[side] } else { 1. };
                        old.l += (groups[side].l as f64 * gain) as f32;
                        old.r += (groups[side].r as f64 * gain) as f32;
                    }
                    let f = self.layer_transition as f64 / (self.sr * 0.005);
                    sample.l = ((sample.l as f64 * (1. - f)) as f32) + ((old.l as f64 * f) as f32);
                    sample.r = ((sample.r as f64 * (1. - f)) as f32) + ((old.r as f64 * f) as f32);
                    self.layer_transition -= 1;
                }
            } else if self.gain > 0. && self.voice.id >= 0 {
                self.voice.advance_parts(b, self.sr);
                self.outgoing.advance_parts(b, self.sr);
                sample = if self.running {
                    self.voice
                        .render(b, (self.beat - self.start_beat).max(0.), delta, self.sr)
                } else {
                    self.voice.tail(b, delta, self.sr)
                };
                if self.transition > 0 {
                    let f = self.transition as f64 / (self.sr * 0.005);
                    let old = self.outgoing.tail(b, delta, self.sr);
                    sample.l = (sample.l as f64 * (1. - f)) as f32 + (old.l as f64 * f) as f32;
                    sample.r = (sample.r as f64 * (1. - f)) as f32 + (old.r as f64 * f) as f32;
                    self.transition -= 1;
                }
            }
            sample = self.filter.process(sample);
            sample.l *= self.gain;
            sample.r *= self.gain;
            sample = self.dynamics.process(sample);
            left[i] = sample.l * self.output_gain;
            right[i] = sample.r * self.output_gain;
            if self.running {
                self.beat += delta;
            }
        }
    }
    pub fn snapshot(&self, b: &Bank) -> Snapshot {
        let mut s = Snapshot {
            beat: self.beat,
            bpm: self.bpm,
            loop_progress: if self.active >= 0 {
                ((self.beat - self.start_beat)
                    / (if self.arranged {
                        self.step_beats
                    } else {
                        Self::beats(b, self.active)
                    }) as f64)
                    .clamp(0., 1.)
            } else {
                0.
            },
            playing: self.running as i32,
            active_loop: self.active,
            mode: self.mode,
            external_clock: self.external as i32,
            clock_state: self.clock_state,
            pending: (self.pending || self.arrangement_pending) as i32,
            active_step: self.arrangement_step,
            ..Snapshot::default()
        };
        if self.arrangement_pending {
            for c in &self.pending_arrangement[..self.pending_arrangement_count] {
                s.queue[s.queue_count as usize] = c.loop_id;
                s.queue_count += 1
            }
        } else if self.arranged {
            for c in &self.arrangement[..self.arrangement_count] {
                s.queue[s.queue_count as usize] = c.loop_id;
                s.queue_count += 1
            }
        } else {
            s.queue_count = (if self.pending {
                self.pending_count
            } else {
                self.cycle_count
            }) as i32;
            for i in 0..s.queue_count as usize {
                s.queue[i] = if self.pending {
                    self.pending_ids[i]
                } else {
                    self.cycle[(self.cycle_pos + i) % self.cycle_count.max(1)]
                };
            }
        }
        s.active_count = if self.arranged {
            self.layer_count
        } else {
            usize::from(self.active >= 0 && self.voice.id >= 0)
        } as i32;
        for i in 0..s.active_count as usize {
            let id = if self.arranged {
                self.layers[i].id
            } else {
                self.active
            };
            s.active_loops[i] = id;
            s.active_tokens[i] = if self.arranged {
                self.layers[i].token
            } else {
                self.active
            };
            let beats = Self::beats(b, id) as f64;
            let start = if self.arranged && self.stacks {
                self.layers[i].start_beat
            } else {
                self.start_beat
            };
            s.active_progress[i] = (self.beat - start).max(0.) % beats / beats;
        }
        s
    }
}

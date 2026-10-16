// Pure, sample-clocked DSP shared by the AudioWorklet and the offline tests.
export class LoopEngine {
  constructor(sampleRate) {
    this.sampleRate = sampleRate;
    this.loops = new Map();
    this.disabled = new Set();
    this.partMasks = new Map();
    this.bpm = this.targetBPM = 120;
    this.beat = this.startBeat = 0;
    this.nudgeRemaining = 0;
    this.nextBar = 4;
    this.active = null;
    this.cycle = [];
    this.cycleIndex = 0;
    this.pending = null;
    this.running = false;
    this.voice = this.tail = null;
    this.arranged = false;
    this.arrangement = [];
    this.pendingArrangement = null;
    this.activeStep = 0;
    this.stepBeats = 4;
    this.layers = [];
    this.oldLayers = [];
    this.gain = 0;
    this.fadeLength = Math.max(1, Math.round(sampleRate * .005));
    this.fade = 0;
    this.slew = 1 - Math.exp(-1 / (sampleRate * .09));
    this.partStep = 1 / (sampleRate * .008);
    this.filter = new OutputFilter(sampleRate);
  }

  load(id, channels, beats) {
    if (!Number.isInteger(id) || !channels.length || channels[0].length < 2 ||
        !Number.isFinite(beats) || beats <= 0 || channels.some(c => c.length !== channels[0].length)) {
      throw new Error('Invalid sample data');
    }
    this.loops.set(id, { channels, beats, frames: channels[0].length, parts: null });
  }

  setParts(id, parts) {
    const loop = this.loops.get(id);
    if (!loop) return;
    if (parts && (parts.length !== 4 || parts.some(p => p.length !== 2 || p.some(c => c.length !== loop.frames)))) throw new Error('Invalid part data');
    loop.parts = parts;
  }
  setPartMask(id, mask) {
    mask &= 15; this.partMasks.set(id, mask);
    for (const voice of [this.voice, this.tail]) if (voice?.id === id) voice.partMask = mask;
  }
  setFilter(type, hz) { this.filter.set(type, hz); }
  advanceParts(voice) {
    if (!voice) return;
    for (let p = 0; p < 4; p++) {
      const target = (voice.partMask & (1 << p)) ? 1 : 0;
      voice.partGain[p] += Math.max(-this.partStep, Math.min(this.partStep, target - voice.partGain[p]));
    }
    voice.partBlend += Math.max(-this.partStep, Math.min(this.partStep, (voice.loop.parts ? 1 : 0) - voice.partBlend));
    voice.audible += Math.max(-this.partStep, Math.min(this.partStep, (voice.partMask ? 1 : 0) - voice.audible));
  }

  valid(id) { return this.loops.has(id) && !this.disabled.has(id); }

  setTempo(bpm) {
    if (Number.isFinite(bpm)) this.targetBPM = Math.min(300, Math.max(30, bpm));
    if (!this.running) this.bpm = this.targetBPM;
  }

  nudge(milliseconds) {
    if (this.running && Number.isFinite(milliseconds)) {
      this.nudgeRemaining += Math.max(-100, Math.min(100, milliseconds)) / 1000 * this.bpm / 60;
    }
  }

  queue(ids) {
    const accepted = [...new Set(ids)].filter(id => this.valid(id));
    if (!accepted.length) return;
    this.pending = accepted;
    this.pendingArrangement = null;
    if (!this.running) {
      this.beat = 0;
      this.nextBar = 4;
      this.bpm = this.targetBPM;
      this.applyPending(0);
    }
  }

  enable(id, enabled) {
    if (enabled) this.disabled.delete(id); else this.disabled.add(id);
    if ((this.arranged || this.pendingArrangement !== null) && !enabled) {
      this.pendingArrangement = (this.pendingArrangement ?? this.arrangement).filter(item => this.valid(item.id));
      return;
    }
    this.cycle = this.cycle.filter(item => this.valid(item));
    this.cycleIndex = Math.max(0, this.cycle.indexOf(this.active));
    if (this.pending) {
      this.pending = this.pending.filter(item => this.valid(item));
      if (!this.pending.length && this.valid(this.active)) this.pending = null;
    }
    // An excluded voice finishes the current bar; it cannot re-enter a cycle.
    if (!this.valid(this.active) && this.active !== null && this.pending === null) {
      this.pending = [...this.cycle];
    }
  }

  stop() {
    this.running = false;
    this.pending = null;
    this.pendingArrangement = null;
    this.nudgeRemaining = 0;
  }

  launch(id, beat) {
    this.tail = this.voice;
    this.fade = this.fadeLength;
    this.active = id;
    this.startBeat = beat;
    this.voice = this.makeVoice(id, id, this.partMasks.get(id) ?? 15);
  }

  makeVoice(id, token, mask) {
    return { id, token, loop: this.loops.get(id), position: 0, partMask: mask,
      partGain: [0, 1, 2, 3].map(p => mask & (1 << p) ? 1 : 0), partBlend: 0, audible: mask ? 1 : 0,
      wrapFade: 0, tailPosition: 0 };
  }

  // Items have independent tokens so even repeated copies can have different parts.
  arrange(items) {
    const perStep = new Map();
    this.pendingArrangement = items.slice(0, 64).filter(item => {
      if (!this.valid(item.id) || !Number.isInteger(item.step) || item.step < 0 || item.step >= 64 || !Number.isInteger(item.token) || item.token <= 0) return false;
      const count = perStep.get(item.step) || 0;
      if (count >= 8) return false;
      perStep.set(item.step, count + 1); return true;
    }).map(item => ({ ...item, mask: item.mask & 15 }));
    this.pending = null;
    if (!this.running) {
      this.beat = 0; this.nextBar = 4; this.bpm = this.targetBPM;
      this.applyArrangement(0);
    }
  }

  setClipMask(token, mask) {
    mask &= 15;
    for (const item of this.arrangement) if (item.token === token) item.mask = mask;
    for (const item of this.pendingArrangement ?? []) if (item.token === token) item.mask = mask;
    for (const voice of [...this.layers, ...this.oldLayers]) if (voice.token === token) voice.partMask = mask;
  }

  nextStep(current) {
    const steps = [...new Set(this.arrangement.filter(item => this.valid(item.id)).map(item => item.step))].sort((a, b) => a - b);
    return steps.find(step => step > current) ?? steps[0] ?? -1;
  }

  launchStep(step, beat) {
    this.oldLayers = this.arranged ? this.layers : (this.voice ? [this.voice] : []);
    this.fade = this.fadeLength;
    this.activeStep = step; this.startBeat = beat;
    this.layers = this.arrangement.filter(item => item.step === step && this.valid(item.id)).slice(0, 8)
      .map(item => this.makeVoice(item.id, item.token, item.mask));
    this.stepBeats = Math.max(1, ...this.layers.map(voice => voice.loop.beats));
    this.active = this.layers[0]?.id ?? null;
  }

  applyArrangement(beat) {
    const keep = this.arranged ? new Set(this.layers.map(layer => layer.token)) : new Set();
    this.arrangement = this.pendingArrangement.filter(item => this.valid(item.id));
    this.pendingArrangement = null; this.pending = null;
    const matching = this.arrangement.find(item => keep.has(item.token));
    const step = matching?.step ?? this.nextStep(-1);
    const nextLayers = this.arrangement.filter(item => item.step === step);
    if (this.running && matching && nextLayers.length === this.layers.length &&
        nextLayers.every(item => this.layers.some(voice => voice.token === item.token && voice.id === item.id))) {
      for (const item of nextLayers) this.layers.find(voice => voice.token === item.token).partMask = item.mask;
      this.activeStep = step;
      return;
    }
    this.launchStep(step, beat); this.arranged = true;
    this.running = this.layers.length > 0;
  }

  applyPending(beat) {
    this.cycle = this.pending.filter(id => this.valid(id));
    this.pending = null;
    if (this.arranged) { this.voice = this.layers[0] ?? null; this.arranged = false; }
    this.cycleIndex = 0;
    if (this.cycle.length) {
      this.launch(this.cycle[0], beat);
      this.running = true;
    } else {
      this.running = false;
      this.active = null;
    }
  }

  read(voice, channel, at = voice?.position) {
    if (!voice) return 0;
    const data = voice.loop.channels[channel] || voice.loop.channels[0];
    const position = Math.min(voice.loop.frames - 1, at);
    const index = Math.floor(position);
    const fraction = position - index;
    const next = Math.min(index + 1, data.length - 1);
    let result = data[index] + (data[next] - data[index]) * fraction;
    if (voice.loop.parts && voice.partBlend > 0) {
      // A solo part is played directly so codec residual from the other three
      // does not remain audible; larger combinations retain the original mix.
      const gains = voice.partGain;
      const originalWeight = Math.max(0, Math.min(1, gains[0] + gains[1] + gains[2] + gains[3] - 1));
      result *= 1 - voice.partBlend + voice.partBlend * originalWeight;
      for (let p = 0; p < 4; p++) {
        const amount = (gains[p] - originalWeight) * voice.partBlend;
        if (!amount) continue;
        const part = voice.loop.parts[p][channel];
        result += amount * (part[index] + (part[next] - part[index]) * fraction);
      }
    }
    return result * voice.audible;
  }

  readLayer(voice, channel) {
    if (!voice.wrapFade) return this.read(voice, channel);
    const mix = voice.wrapFade / this.fadeLength;
    return this.read(voice, channel) * (1 - mix) + this.read(voice, channel, voice.tailPosition) * mix;
  }

  render(left, right) {
    for (let frame = 0; frame < left.length; frame++) {
      this.bpm += (this.targetBPM - this.bpm) * this.slew;
      const maxAdjustment = this.bpm * .18 / (60 * this.sampleRate);
      const adjustment = this.running ? Math.max(-maxAdjustment, Math.min(maxAdjustment, this.nudgeRemaining / (.12 * this.sampleRate))) : 0;
      this.nudgeRemaining -= adjustment;
      const delta = this.bpm / (60 * this.sampleRate) + adjustment;
      if (this.running) {
        if (this.beat + 1e-9 >= this.nextBar) {
          const boundary = this.nextBar;
          this.nextBar += 4;
          if (this.pendingArrangement !== null) this.applyArrangement(boundary);
          else if (this.pending !== null) this.applyPending(boundary);
        }
        if (this.running && this.arranged && this.beat - this.startBeat + 1e-9 >= this.stepBeats) {
          this.launchStep(this.nextStep(this.activeStep), this.startBeat + this.stepBeats);
        } else if (this.running && !this.arranged && this.beat - this.startBeat + 1e-9 >= this.voice.loop.beats) {
          const boundary = this.startBeat + this.voice.loop.beats;
          this.cycleIndex = (this.cycleIndex + 1) % this.cycle.length;
          this.launch(this.cycle[this.cycleIndex], boundary);
        }
      }
      const target = this.running ? 1 : 0;
      this.gain += Math.max(-1 / (this.sampleRate * .008), Math.min(1 / (this.sampleRate * .003), target - this.gain));
      const mix = this.fade / this.fadeLength;
      if (this.arranged) {
        let l = 0, r = 0, oldL = 0, oldR = 0;
        for (const voice of this.layers) { this.advanceParts(voice); l += this.readLayer(voice, 0); r += this.readLayer(voice, 1); }
        if (this.fade) for (const voice of this.oldLayers) { this.advanceParts(voice); oldL += this.read(voice, 0); oldR += this.read(voice, 1); }
        left[frame] = (l / Math.max(1, this.layers.length) * (1 - mix) + oldL / Math.max(1, this.oldLayers.length) * mix) * this.gain;
        right[frame] = (r / Math.max(1, this.layers.length) * (1 - mix) + oldR / Math.max(1, this.oldLayers.length) * mix) * this.gain;
        for (const voice of this.layers) {
          const step = delta / voice.loop.beats * voice.loop.frames;
          voice.position += step; voice.tailPosition += step;
          if (voice.wrapFade > 0) voice.wrapFade--;
          if (voice.position >= voice.loop.frames) { voice.tailPosition = voice.position; voice.position %= voice.loop.frames; voice.wrapFade = this.fadeLength; }
        }
        if (this.fade) for (const voice of this.oldLayers) voice.position += delta / voice.loop.beats * voice.loop.frames;
      } else {
        this.advanceParts(this.voice); this.advanceParts(this.tail);
        left[frame] = (this.read(this.voice, 0) * (1 - mix) + this.read(this.tail, 0) * mix) * this.gain;
        right[frame] = (this.read(this.voice, 1) * (1 - mix) + this.read(this.tail, 1) * mix) * this.gain;
        if (this.voice) this.voice.position += delta / this.voice.loop.beats * this.voice.loop.frames;
        if (this.tail) this.tail.position += delta / this.tail.loop.beats * this.tail.loop.frames;
      }
      this.filter.process(left, right, frame);
      if (this.fade > 0 && --this.fade === 0) { this.tail = null; this.oldLayers = []; }
      if (this.running) this.beat += delta;
    }
  }

  snapshot() {
    return {
      playing: this.running, active: this.active, beat: this.beat, bpm: this.bpm,
      progress: this.active !== null ? Math.min(1, Math.max(0, (this.beat - this.startBeat) / (this.arranged ? this.stepBeats : this.voice.loop.beats))) : 0,
      pending: this.pending !== null || this.pendingArrangement !== null,
      queue: this.pendingArrangement?.map(item => item.id) ?? (this.arranged ? this.arrangement.map(item => item.id) : this.pending ?? this.cycle),
      activeStep: this.activeStep,
      activeLoops: this.arranged ? this.layers.map(voice => voice.id) : (this.active === null ? [] : [this.active]),
      activeTokens: this.arranged ? this.layers.map(voice => voice.token) : (this.active === null ? [] : [this.active]),
      activeProgress: this.arranged ? this.layers.map(voice => (voice.position % voice.loop.frames) / voice.loop.frames) : (this.voice ? [Math.min(1, this.voice.position / this.voice.loop.frames)] : []),
    };
  }
}

class OutputFilter {
  constructor(sr) {
    this.sr = sr; this.type = 0; this.mix = 0;
    this.current = [1, 0, 0, 0, 0]; this.target = [...this.current];
    this.z1 = [0, 0]; this.z2 = [0, 0]; this.slew = 1 - Math.exp(-1 / (sr * .012));
  }
  set(type, hz) {
    this.type = Math.max(0, Math.min(3, Math.round(type)));
    hz = Math.max(20, Math.min(this.sr * .45, hz));
    if (!this.type || !Number.isFinite(hz)) return;
    const omega = 2 * Math.PI * hz / this.sr, c = Math.cos(omega), a = Math.sin(omega) / (2 * Math.SQRT1_2), d = 1 + a;
    if (this.type === 1) this.target = [(1-c)/(2*d),(1-c)/d,(1-c)/(2*d),-2*c/d,(1-a)/d];
    else if (this.type === 2) this.target = [a/d,0,-a/d,-2*c/d,(1-a)/d];
    else this.target = [(1+c)/(2*d),-(1+c)/d,(1+c)/(2*d),-2*c/d,(1-a)/d];
  }
  process(left, right, frame) {
    for (let i = 0; i < 5; i++) this.current[i] += (this.target[i] - this.current[i]) * this.slew;
    this.mix += ((this.type ? 1 : 0) - this.mix) * this.slew;
    for (let i = 0; i < 2; i++) {
      const channel = i ? right : left, x = channel[frame], c = this.current;
      const y = c[0]*x + this.z1[i];
      this.z1[i] = c[1]*x - c[3]*y + this.z2[i]; this.z2[i] = c[2]*x - c[4]*y;
      channel[frame] = x + this.mix * (y - x);
    }
  }
}

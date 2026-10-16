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
    this.loops.set(id, { channels, beats, frames: channels[0].length, parts: null,
      partMask: this.partMasks.get(id) ?? 15, partGain: [1,1,1,1], partBlend: 0, audible: 1 });
  }

  setParts(id, parts) {
    const loop = this.loops.get(id);
    if (!loop) return;
    if (parts && (parts.length !== 4 || parts.some(p => p.length !== 2 || p.some(c => c.length !== loop.frames)))) throw new Error('Invalid part data');
    loop.parts = parts;
  }
  setPartMask(id, mask) {
    mask &= 15; this.partMasks.set(id, mask);
    const loop = this.loops.get(id); if (loop) loop.partMask = mask;
  }
  setFilter(type, hz) { this.filter.set(type, hz); }
  advanceParts(loop) {
    if (!loop) return;
    for (let p = 0; p < 4; p++) {
      const target = (loop.partMask & (1 << p)) ? 1 : 0;
      loop.partGain[p] += Math.max(-this.partStep, Math.min(this.partStep, target - loop.partGain[p]));
    }
    loop.partBlend += Math.max(-this.partStep, Math.min(this.partStep, (loop.parts ? 1 : 0) - loop.partBlend));
    loop.audible += Math.max(-this.partStep, Math.min(this.partStep, (loop.partMask ? 1 : 0) - loop.audible));
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
    if (!this.running) {
      this.beat = 0;
      this.nextBar = 4;
      this.bpm = this.targetBPM;
      this.applyPending(0);
    }
  }

  enable(id, enabled) {
    if (enabled) this.disabled.delete(id); else this.disabled.add(id);
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
    this.nudgeRemaining = 0;
  }

  launch(id, beat) {
    this.tail = this.voice;
    this.fade = this.fadeLength;
    this.active = id;
    this.startBeat = beat;
    this.voice = { loop: this.loops.get(id), position: 0 };
  }

  applyPending(beat) {
    this.cycle = this.pending.filter(id => this.valid(id));
    this.pending = null;
    this.cycleIndex = 0;
    if (this.cycle.length) {
      this.launch(this.cycle[0], beat);
      this.running = true;
    } else {
      this.running = false;
      this.active = null;
    }
  }

  read(voice, channel) {
    if (!voice) return 0;
    const data = voice.loop.channels[channel] || voice.loop.channels[0];
    const position = Math.min(voice.loop.frames - 1, voice.position);
    const index = Math.floor(position);
    const fraction = position - index;
    const next = Math.min(index + 1, data.length - 1);
    let result = data[index] + (data[next] - data[index]) * fraction;
    if (voice.loop.parts && voice.loop.partBlend > 0) {
      // A solo part is played directly so codec residual from the other three
      // does not remain audible; larger combinations retain the original mix.
      const gains = voice.loop.partGain;
      const originalWeight = Math.max(0, Math.min(1, gains[0] + gains[1] + gains[2] + gains[3] - 1));
      result *= 1 - voice.loop.partBlend + voice.loop.partBlend * originalWeight;
      for (let p = 0; p < 4; p++) {
        const amount = (gains[p] - originalWeight) * voice.loop.partBlend;
        if (!amount) continue;
        const part = voice.loop.parts[p][channel];
        result += amount * (part[index] + (part[next] - part[index]) * fraction);
      }
    }
    return result * voice.loop.audible;
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
          if (this.pending !== null) this.applyPending(boundary);
        }
        if (this.running && this.beat - this.startBeat + 1e-9 >= this.voice.loop.beats) {
          const boundary = this.startBeat + this.voice.loop.beats;
          this.cycleIndex = (this.cycleIndex + 1) % this.cycle.length;
          this.launch(this.cycle[this.cycleIndex], boundary);
        }
      }
      const target = this.running ? 1 : 0;
      this.advanceParts(this.voice?.loop);
      if (this.tail?.loop !== this.voice?.loop) this.advanceParts(this.tail?.loop);
      this.gain += Math.max(-1 / (this.sampleRate * .008), Math.min(1 / (this.sampleRate * .003), target - this.gain));
      const mix = this.fade / this.fadeLength;
      left[frame] = (this.read(this.voice, 0) * (1 - mix) + this.read(this.tail, 0) * mix) * this.gain;
      right[frame] = (this.read(this.voice, 1) * (1 - mix) + this.read(this.tail, 1) * mix) * this.gain;
      this.filter.process(left, right, frame);
      if (this.voice) this.voice.position += delta / this.voice.loop.beats * this.voice.loop.frames;
      if (this.tail) this.tail.position += delta / this.tail.loop.beats * this.tail.loop.frames;
      if (this.fade > 0 && --this.fade === 0) this.tail = null;
      if (this.running) this.beat += delta;
    }
  }

  snapshot() {
    return {
      playing: this.running, active: this.active, beat: this.beat, bpm: this.bpm,
      progress: this.voice ? Math.min(1, Math.max(0, (this.beat - this.startBeat) / this.voice.loop.beats)) : 0,
      pending: this.pending !== null,
      queue: this.pending ?? this.cycle,
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

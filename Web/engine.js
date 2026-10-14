// Pure, sample-clocked DSP shared by the AudioWorklet and the offline tests.
export class LoopEngine {
  constructor(sampleRate) {
    this.sampleRate = sampleRate;
    this.loops = new Map();
    this.disabled = new Set();
    this.bpm = this.targetBPM = 120;
    this.beat = this.startBeat = 0;
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
  }

  load(id, channels, beats) {
    if (!Number.isInteger(id) || !channels.length || channels[0].length < 2 ||
        !Number.isFinite(beats) || beats <= 0 || channels.some(c => c.length !== channels[0].length)) {
      throw new Error('Invalid sample data');
    }
    this.loops.set(id, { channels, beats, frames: channels[0].length });
  }

  valid(id) { return this.loops.has(id) && !this.disabled.has(id); }

  setTempo(bpm) {
    if (Number.isFinite(bpm)) this.targetBPM = Math.min(300, Math.max(30, bpm));
    if (!this.running) this.bpm = this.targetBPM;
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
    return data[index] + (data[Math.min(index + 1, data.length - 1)] - data[index]) * fraction;
  }

  render(left, right) {
    for (let frame = 0; frame < left.length; frame++) {
      this.bpm += (this.targetBPM - this.bpm) * this.slew;
      const delta = this.bpm / (60 * this.sampleRate);
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
      this.gain += Math.max(-1 / (this.sampleRate * .008), Math.min(1 / (this.sampleRate * .003), target - this.gain));
      const mix = this.fade / this.fadeLength;
      left[frame] = (this.read(this.voice, 0) * (1 - mix) + this.read(this.tail, 0) * mix) * this.gain;
      right[frame] = (this.read(this.voice, 1) * (1 - mix) + this.read(this.tail, 1) * mix) * this.gain;
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

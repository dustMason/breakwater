export class AudioPlayer {
  constructor(onState, onProgress, onInterruption) {
    this.onState = onState;
    this.onProgress = onProgress;
    this.onInterruption = onInterruption;
    this.context = this.node = this.output = null;
    this.loaded = new Set();
    this.initializing = null;
    this.inFlight = new Map();
    this.tempo = 120;
    this.volume = .8;
  }

  async unlock() {
    if (!window.isSecureContext) throw new Error('Open Breakwater over HTTPS or localhost to enable audio.');
    if (!this.context) {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) throw new Error('This browser does not support Web Audio. Try a current Safari, Chrome, or Firefox.');
      this.context = new Context({ latencyHint: 'interactive' });
      this.context.onstatechange = () => {
        if (this.context.state !== 'running') {
          this.stop();
          this.onInterruption();
        }
      };
    }
    // Called directly from the gesture, before fetching or decoding anything.
    const resumed = this.context.resume();
    if (!this.initializing) this.initializing = this.initialize().catch(error => {
      this.initializing = null;
      throw error;
    });
    await Promise.all([resumed, this.initializing]);
  }

  async initialize() {
    if (!this.context.audioWorklet) throw new Error('AudioWorklet is unavailable. Try a current Safari, Chrome, or Firefox.');
    await this.context.audioWorklet.addModule(new URL('./audio-worklet.js', import.meta.url));
    this.node = new AudioWorkletNode(this.context, 'breakwater', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
    this.output = this.context.createGain();
    this.output.gain.value = this.volume;
    this.node.connect(this.output).connect(this.context.destination);
    this.node.port.onmessage = ({ data }) => this.onState(data);
    this.node.onprocessorerror = () => this.onInterruption('Audio stopped unexpectedly. Reload the page to restart it.');
    this.setTempo(this.tempo);
  }

  async load(samples, disabled, onProgress = this.onProgress) {
    const requested = [...new Map(samples.map(sample => [sample.id, sample])).values()];
    let cursor = 0, done = 0;
    const errors = [];
    const ensure = sample => {
      if (this.loaded.has(sample.id)) return Promise.resolve();
      if (!this.inFlight.has(sample.id)) {
        const pending = (async () => {
          const response = await fetch(new URL(`./Samples/${sample.file}`, import.meta.url));
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const buffer = await this.context.decodeAudioData(await response.arrayBuffer());
          const channels = Array.from({ length: buffer.numberOfChannels }, (_, i) => buffer.getChannelData(i).slice());
          this.node.port.postMessage({ type: 'load', id: sample.id, beats: sample.beats, channels }, channels.map(channel => channel.buffer));
          this.enable(sample.id, !disabled.has(sample.id));
          this.loaded.add(sample.id);
        })().finally(() => this.inFlight.delete(sample.id));
        this.inFlight.set(sample.id, pending);
      }
      return this.inFlight.get(sample.id);
    };
    await Promise.all(Array.from({ length: Math.min(4, requested.length) }, async () => {
      while (cursor < requested.length) {
        const sample = requested[cursor++];
        try { await ensure(sample); }
        catch (error) { errors.push(`${sample.file}: ${error.message}`); }
        onProgress(++done, requested.length);
      }
    }));
    if (errors.length) throw new Error(`Couldn't load ${errors.length} loop${errors.length === 1 ? '' : 's'}. Check your connection and press Retry. (${errors[0]})`);
  }

  command(data) { this.node?.port.postMessage(data); }
  queue(ids) { this.command({ type: 'queue', ids }); }
  stop() { this.command({ type: 'stop' }); }
  enable(id, enabled) { this.command({ type: 'enable', id, enabled }); }
  setTempo(bpm) { this.tempo = bpm; this.command({ type: 'tempo', bpm }); }
  setVolume(value) {
    this.volume = value;
    if (this.output) this.output.gain.setTargetAtTime(value, this.context.currentTime, .015);
  }
}

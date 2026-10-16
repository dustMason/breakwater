import { assetURL } from './assets.js';

export class AudioPlayer {
  constructor(onState, onProgress, onInterruption) {
    this.onState = onState;
    this.onProgress = onProgress;
    this.onInterruption = onInterruption;
    this.assetBaseURL = new URL('./local-assets/', import.meta.url);
    this.context = this.node = this.output = null;
    this.loaded = new Set();
    this.initializing = null;
    this.inFlight = new Map();
    this.partCache = new Map();
    this.partInFlight = new Map();
    this.frameCounts = new Map();
    this.partPins = new Set();
    this.tempo = 120;
    this.volume = .8;
    this.filter = { mode: 0, hz: 1200 };
    this.masks = new Map();
    this.requests = new Map();
    this.nextRequest = 1;
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
      this.node?.disconnect();
      this.output?.disconnect();
      this.node = this.output = null;
      throw error;
    });
    await Promise.all([resumed, this.initializing]);
  }

  async initialize() {
    if (!this.context.audioWorklet) throw new Error('AudioWorklet is unavailable. Try a current Safari, Chrome, or Firefox.');
    const [response] = await Promise.all([
      fetch(new URL('./breakwater_audio.wasm', import.meta.url)),
      this.context.audioWorklet.addModule(new URL('./audio-worklet.js', import.meta.url)),
    ]);
    if (!response.ok) throw new Error(`Couldn't load the audio engine (HTTP ${response.status}).`);
    const module = await WebAssembly.compile(await response.arrayBuffer());
    this.node = new AudioWorkletNode(this.context, 'breakwater', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2], processorOptions: { module } });
    this.output = this.context.createGain();
    this.output.gain.value = this.volume;
    this.node.connect(this.output).connect(this.context.destination);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Audio engine did not start. Reload the page to retry.')), 15000);
      this.node.port.onmessage = ({ data }) => {
        if (data.type === 'ready' || data.type === 'ready-error') {
          clearTimeout(timeout);
          if (data.type === 'ready') resolve(); else reject(new Error(data.error));
        } else this.receive(data);
      };
      this.node.onprocessorerror = () => {
        clearTimeout(timeout);
        const error = new Error('Audio stopped unexpectedly. Reload the page to restart it.');
        for (const request of this.requests.values()) request.reject(error);
        this.requests.clear();
        reject(error);
        this.onInterruption(error.message);
      };
      this.node.port.postMessage({ type: 'init' });
    });
    this.setTempo(this.tempo);
    this.setFilter(this.filter.mode, this.filter.hz);
    for (const [id, mask] of this.masks) this.command({ type: 'part-mask', ids: [id], mask });
  }

  receive(data) {
    if (data.type === 'state') { this.onState(data.state); return; }
    if (data.type === 'load-complete' || data.type === 'load-error') {
      const request = this.requests.get(data.request);
      if (!request) return;
      this.requests.delete(data.request);
      if (data.type === 'load-error') request.reject(new Error(data.error)); else request.resolve();
    }
  }

  transfer(data, buffers) {
    const request = this.nextRequest++;
    return new Promise((resolve, reject) => {
      this.requests.set(request, { resolve, reject });
      try { this.node.port.postMessage({ ...data, request }, buffers); }
      catch (error) { this.requests.delete(request); reject(error); }
    });
  }

  async load(samples, disabled, onProgress = this.onProgress) {
    const requested = [...new Map(samples.map(sample => [sample.id, sample])).values()];
    let cursor = 0, done = 0;
    const errors = [];
    const ensure = sample => {
      if (this.loaded.has(sample.id)) return Promise.resolve();
      if (!this.inFlight.has(sample.id)) {
        const pending = (async () => {
          const response = await fetch(assetURL(this.assetBaseURL, sample.file));
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const buffer = await this.context.decodeAudioData(await response.arrayBuffer());
          const channels = Array.from({ length: Math.min(2, buffer.numberOfChannels) }, (_, i) => buffer.getChannelData(i).slice());
          this.frameCounts.set(sample.id, channels[0].length);
          await this.transfer({ type: 'load', id: sample.id, beats: sample.beats, channels }, channels.map(channel => channel.buffer));
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
  arrange(items) { this.command({ type: 'arrange', items }); }
  setClipMask(token, mask) { this.command({ type: 'clip-mask', token, mask }); }
  stop() { this.command({ type: 'stop' }); }
  enable(id, enabled) { this.command({ type: 'enable', id, enabled }); }
  setTempo(bpm) { this.tempo = bpm; this.command({ type: 'tempo', bpm }); }
  nudge(milliseconds) { this.command({ type: 'nudge', milliseconds }); }
  setFilter(mode, hz) { this.filter = { mode, hz }; this.command({ type: 'filter', mode, hz }); }
  setPartMask(ids, mask) {
    for (const id of ids) this.masks.set(id, mask);
    this.command({ type: 'part-mask', ids, mask });
  }
  pinParts(ids) { this.partPins = new Set(ids); }
  async loadParts(sample) {
    if (!sample?.parts || !this.loaded.has(sample.id)) return;
    if (this.partCache.has(sample.id)) { this.partCache.delete(sample.id); this.partCache.set(sample.id, true); return; }
    if (!this.partInFlight.has(sample.id)) {
      const pending = (async () => {
        const frames = this.frameCounts.get(sample.id);
        const parts = await Promise.all(sample.parts.files.map(async path => {
          const response = await fetch(assetURL(this.assetBaseURL, path));
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const buffer = await this.context.decodeAudioData(await response.arrayBuffer());
          if (Math.abs(buffer.length - frames) > 2048) throw new Error('Unexpected part duration');
          return [0, 1].map(ch => {
            const out = new Float32Array(frames);
            const source = buffer.getChannelData(Math.min(ch, buffer.numberOfChannels - 1));
            out.set(source.subarray(0, Math.min(frames, source.length)));
            return out;
          });
        }));
        await this.transfer({ type: 'parts', id: sample.id, parts }, parts.flat().map(channel => channel.buffer));
        this.partCache.set(sample.id, true);
        const pinned = new Set([sample.id, ...this.partPins]);
        for (const id of this.partCache.keys()) {
          if (this.partCache.size <= 6) break;
          if (!pinned.has(id)) { this.partCache.delete(id); this.command({ type: 'parts', id, parts: null }); }
        }
      })().finally(() => this.partInFlight.delete(sample.id));
      this.partInFlight.set(sample.id, pending);
    }
    return this.partInFlight.get(sample.id);
  }
  setVolume(value) {
    this.volume = value;
    if (this.output) this.output.gain.setTargetAtTime(value, this.context.currentTime, .015);
  }
}

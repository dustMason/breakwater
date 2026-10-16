import { WasmEngine } from './wasm-engine.js?v=6';

const COPY_FLOATS_PER_BLOCK = 16384;
class BreakwaterProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.jobs = [];
    this.framesSinceUpdate = 0;
    try { this.engine = new WasmEngine(new WebAssembly.Instance(options.processorOptions.module), sampleRate); }
    catch (error) { this.initializationError = String(error); }
    this.port.onmessage = ({ data }) => {
      if (data.type === 'init') {
        this.port.postMessage(this.initializationError ? { type: 'ready-error', error: this.initializationError } : { type: 'ready' });
        return;
      }
      if (!this.engine) return;
      const e = this.engine;
      try {
        switch (data.type) {
          case 'load': this.jobs.push({ ...e.beginLoad(data.id, data.channels, data.beats), request: data.request }); break;
          case 'parts':
            if (data.parts) this.jobs.push({ ...e.beginParts(data.id, data.parts), request: data.request });
            else e.setParts(data.id, null);
            break;
          case 'queue': e.queue(data.ids); break;
          case 'arrange': e.arrange(data.items); break;
          case 'stacks': e.stacks(data.items, data.start); break;
          case 'crossfade': e.setCrossfade(data.position); break;
          case 'clip-mask': e.setClipMask(data.token, data.mask); break;
          case 'clip-filter': e.setClipFilter(data.token, data.mode, data.hz); break;
          case 'clip-level': e.setClipLevel(data.token, data.level); break;
          case 'enable': e.enable(data.id, data.enabled); break;
          case 'tempo': e.setTempo(data.bpm); break;
          case 'nudge': e.nudge(data.milliseconds); break;
          case 'part-mask': for (const id of data.ids) e.setPartMask(id, data.mask); break;
          case 'filter': e.setFilter(data.mode, data.hz); break;
          case 'stop': e.stop(); break;
        }
      } catch (error) { if (data.request) this.port.postMessage({ type: 'load-error', request: data.request, error: String(error) }); }
    };
  }
  process(_inputs, outputs) {
    const [left, right] = outputs[0];
    if (!this.engine) return true;
    this.engine.render(left, right, currentFrame / sampleRate);
    if (this.jobs.length) {
      const job = this.jobs[0];
      try {
        if (this.engine.copy(job, COPY_FLOATS_PER_BLOCK)) {
          this.engine.finish(job); this.jobs.shift();
          this.port.postMessage({ type: 'load-complete', request: job.request });
        }
      } catch (error) {
        this.engine.discard(job); this.jobs.shift();
        this.port.postMessage({ type: 'load-error', request: job.request, error: String(error) });
      }
    }
    this.framesSinceUpdate += left.length;
    if (this.framesSinceUpdate >= sampleRate / 30) { this.framesSinceUpdate = 0; this.port.postMessage({ type: 'state', state: this.engine.snapshot() }); }
    return true;
  }
}
registerProcessor('breakwater', BreakwaterProcessor);

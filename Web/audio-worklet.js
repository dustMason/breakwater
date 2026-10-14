import { LoopEngine } from './engine.js';

class BreakwaterProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.engine = new LoopEngine(sampleRate);
    this.framesSinceUpdate = 0;
    this.port.onmessage = ({ data }) => {
      const e = this.engine;
      switch (data.type) {
        case 'load': e.load(data.id, data.channels, data.beats); break;
        case 'queue': e.queue(data.ids); break;
        case 'enable': e.enable(data.id, data.enabled); break;
        case 'tempo': e.setTempo(data.bpm); break;
        case 'stop': e.stop(); break;
      }
      this.sendState();
    };
  }
  sendState() { this.port.postMessage(this.engine.snapshot()); }
  process(_inputs, outputs) {
    const [left, right] = outputs[0];
    this.engine.render(left, right);
    this.framesSinceUpdate += left.length;
    if (this.framesSinceUpdate >= sampleRate / 30) {
      this.framesSinceUpdate = 0;
      this.sendState();
    }
    return true;
  }
}
registerProcessor('breakwater', BreakwaterProcessor);

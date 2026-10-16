import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { WasmEngine } from '../../Web/wasm-engine.js';

const module = new WebAssembly.Module(readFileSync(new URL('../../Rust/target/wasm32-unknown-unknown/release/breakwater_audio.wasm', import.meta.url)));

test('all partial DrumSep masks sum estimates without original-only residuals', () => {
  const rate = 48000, frames = rate * 2;
  const engine = new WasmEngine(new WebAssembly.Instance(module), rate);
  const frequencies = [180, 600, 2400, 7000];
  const parts = frequencies.map(hz => {
    const channel = Float32Array.from({ length: frames }, (_, i) => .1 * Math.sin(2 * Math.PI * hz * i / rate));
    return [channel, channel];
  });
  // DrumSep estimates deliberately do not contain this original-only tone.
  const original = Float32Array.from({ length: frames }, (_, i) => parts.reduce((sum, p) => sum + p[0][i], 0) + .04 * Math.sin(2 * Math.PI * 1000 * i / rate));
  engine.load(1, [original, original], 4);
  engine.setParts(1, parts);
  engine.queue([1]);
  const render = count => {
    const l = new Float32Array(count), r = new Float32Array(count);
    engine.render(l, r);
    assert.ok(l.every(Number.isFinite));
    return l;
  };
  const amplitude = (audio, hz) => {
    let a = 0, b = 0;
    audio.forEach((v, i) => { a += v * Math.sin(2 * Math.PI * hz * i / rate); b += v * Math.cos(2 * Math.PI * hz * i / rate); });
    return 2 * Math.hypot(a, b) / audio.length;
  };
  render(rate / 2);
  for (let mask = 1; mask < 15; mask++) {
    engine.setPartMask(1, mask); render(rate / 10);
    const audio = render(rate);
    assert.ok(amplitude(audio, 1000) < .005, `residual in mask ${mask}`);
    frequencies.forEach((hz, part) => {
      const level = amplitude(audio, hz);
      assert.ok(mask & (1 << part) ? level > .09 : level < .005, `incorrect part ${part} in mask ${mask}`);
    });
  }
  engine.setPartMask(1, 15); render(rate / 10);
  assert.ok(amplitude(render(rate), 1000) > .035, 'All on must restore the original');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const module = new WebAssembly.Module(readFileSync(new URL('../../Rust/target/wasm32-unknown-unknown/release/breakwater_audio.wasm', import.meta.url)));
let Processor;
globalThis.sampleRate = 48000;
globalThis.currentFrame = 0;
globalThis.AudioWorkletProcessor = class { constructor() { this.messages = []; this.port = { postMessage: message => this.messages.push(message) }; } };
globalThis.registerProcessor = (_name, constructor) => { Processor = constructor; };
await import('../../Web/audio-worklet.js');

function send(processor, data) { processor.port.onmessage({ data }); }
function block(processor) {
  const left = new Float32Array(128), right = new Float32Array(128);
  processor.process([], [[left, right]]); globalThis.currentFrame += 128;
  return left;
}

test('worklet stages samples in bounded pieces, acknowledges publication and keeps rendering during parts loads', () => {
  const p = new Processor({ processorOptions: { module } });
  send(p, { type: 'init' }); assert.equal(p.messages.at(-1).type, 'ready');
  const frames = 50000, mono = new Float32Array(frames).fill(.25);
  send(p, { type: 'load', id: 4, channels: [mono], beats: 4, request: 1 });
  for (let i = 0; i < 6; i++) { block(p); assert.ok(!p.messages.some(m => m.request === 1)); }
  block(p); assert.ok(p.messages.some(m => m.type === 'load-complete' && m.request === 1));
  send(p, { type: 'arrange', items: [{ id: 4, token: 17, step: 0, mask: 15 }] });
  for (let i = 0; i < 10; i++) block(p);
  assert.ok(block(p).some(value => value > .1));
  const parts = Array.from({ length: 4 }, () => [new Float32Array(frames).fill(.0625), new Float32Array(frames).fill(.0625)]);
  send(p, { type: 'parts', id: 4, parts, request: 2 });
  for (let i = 0; i < 24; i++) { assert.ok(block(p).some(value => value > .1)); assert.ok(!p.messages.some(m => m.request === 2)); }
  block(p); assert.ok(p.messages.some(m => m.type === 'load-complete' && m.request === 2));
  send(p, { type: 'clip-mask', token: 17, mask: 0 });
  for (let i = 0; i < 8; i++) block(p);
  assert.ok(block(p).every(value => Math.abs(value) < 1e-6));
  p.engine.destroy();
});

test('worklet reports invalid and duplicate transfers without publishing or double-freeing', () => {
  const p = new Processor({ processorOptions: { module } });
  send(p, { type: 'load', id: -1, channels: [new Float32Array(32)], beats: 4, request: 1 });
  assert.ok(p.messages.some(m => m.type === 'load-error' && m.request === 1));
  const channels = [new Float32Array(32).fill(.2)];
  send(p, { type: 'load', id: 1, channels, beats: 4, request: 2 }); block(p);
  assert.ok(p.messages.some(m => m.type === 'load-complete' && m.request === 2));
  send(p, { type: 'load', id: 1, channels, beats: 4, request: 3 }); block(p);
  assert.ok(p.messages.some(m => m.type === 'load-error' && m.request === 3));
  send(p, { type: 'parts', id: 1, parts: [[new Float32Array(2), new Float32Array(2)]], request: 4 });
  assert.ok(p.messages.some(m => m.type === 'load-error' && m.request === 4));
  p.engine.destroy();
});

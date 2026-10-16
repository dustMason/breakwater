import test from 'node:test';
import assert from 'node:assert/strict';
import { AudioPlayer } from '../../Web/audio.js';

const object = (id, extension = 'wav') => `objects/${id.toString(16).padStart(64, '0')}.${extension}`;
const clip = id => ({ id, beats: 4, file: object(id) });
function player() {
  const sent = [];
  const p = new AudioPlayer(() => {}, () => {}, () => {});
  p.context = { decodeAudioData: async () => ({ numberOfChannels: 1, getChannelData: () => new Float32Array(8) }) };
  p.node = { port: { postMessage: data => { sent.push(data); if (data.request) queueMicrotask(() => p.receive({ type: 'load-complete', request: data.request })); } } };
  return { p, sent };
}

test('on-demand loads fetch only requested IDs and deduplicate overlapping gestures', async t => {
  const { p, sent } = player();
  const fetched = [];
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  t.mock.method(globalThis, 'fetch', async url => {
    fetched.push(url.pathname);
    await gate;
    return { ok: true, arrayBuffer: async () => new ArrayBuffer(8) };
  });
  const first = p.load([clip(60)], new Set());
  const second = p.load([clip(60), clip(257)], new Set());
  release();
  await Promise.all([first, second]);
  assert.equal(fetched.length, 2);
  assert.ok(fetched.some(path => path.endsWith(object(60))));
  assert.ok(fetched.some(path => path.endsWith(object(257))));
  assert.deepEqual(sent.filter(item => item.type === 'load').map(item => item.id).sort((a,b) => a-b), [60,257]);
  await p.load([clip(60)], new Set());
  assert.equal(fetched.length, 2);
});

test('a decoded sample is not published until the worklet confirms it, and a failed transfer can retry', async t => {
  const { p, sent } = player();
  p.node.port.postMessage = data => sent.push(data);
  t.mock.method(globalThis, 'fetch', async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) }));
  const first = p.load([clip(60)], new Set());
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(p.loaded.has(60), false);
  const initial = sent.find(item => item.type === 'load');
  p.receive({ type: 'load-error', request: initial.request, error: 'transfer failed' });
  await assert.rejects(first, /transfer failed/);
  assert.equal(p.requests.size, 0);
  const retry = p.load([clip(60)], new Set());
  await new Promise(resolve => setImmediate(resolve));
  const last = sent.filter(item => item.type === 'load').at(-1);
  p.receive({ type: 'load-complete', request: last.request });
  await retry;
  assert.equal(p.loaded.has(60), true);
});

test('failed samples can retry without re-fetching successes; exclusions are read after decoding', async t => {
  const { p, sent } = player();
  const disabled = new Set();
  let fail = true;
  const fetched = [];
  t.mock.method(globalThis, 'fetch', async url => {
    fetched.push(url.pathname);
    if (url.pathname.endsWith(object(61)) && fail) return { ok: false, status: 503 };
    disabled.add(60);
    return { ok: true, arrayBuffer: async () => new ArrayBuffer(8) };
  });
  await assert.rejects(p.load([clip(60),clip(61)], disabled), /Couldn't load 1 loop/);
  assert.ok(p.loaded.has(60));
  assert.equal(p.inFlight.size, 0);
  assert.ok(sent.some(item => item.type === 'enable' && item.id === 60 && !item.enabled));
  fail = false;
  await p.load([clip(60),clip(61)], disabled);
  assert.equal(fetched.length, 3);
  assert.ok(p.loaded.has(61));
});

test('part downloads are shared, retryable, and bounded while active loops stay pinned', async t => {
  const { p, sent } = player();
  p.context.decodeAudioData = async () => ({ length: 8, numberOfChannels: 2, getChannelData: () => new Float32Array(8) });
  const fetched = [];
  let fail = true;
  t.mock.method(globalThis, 'fetch', async url => {
    fetched.push(url.pathname);
    if (fail && url.pathname.endsWith(object(3, 'm4a'))) return { ok: false, status: 503 };
    return { ok: true, arrayBuffer: async () => new ArrayBuffer(8) };
  });
  const sample = id => ({ id, parts: { files: [0,1,2,3].map(n => object(id * 4 + n, 'm4a')) } });
  for (let id = 0; id < 8; id++) { p.loaded.add(id); p.frameCounts.set(id, 8); }
  await assert.rejects(p.loadParts(sample(0)), /HTTP 503/);
  assert.equal(p.partInFlight.size, 0);
  fail = false;
  const both = [p.loadParts(sample(0)), p.loadParts(sample(0))];
  await Promise.all(both);
  assert.equal(sent.filter(item => item.type === 'parts' && item.id === 0 && item.parts).length, 1);
  assert.equal(fetched.length, 8);
  p.pinParts([0]);
  for (let id = 1; id < 8; id++) await p.loadParts(sample(id));
  assert.equal(p.partCache.size, 6);
  assert.ok(p.partCache.has(0));
  assert.ok(sent.some(item => item.type === 'parts' && item.parts === null));
});

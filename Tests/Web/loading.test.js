import test from 'node:test';
import assert from 'node:assert/strict';
import { AudioPlayer } from '../../Web/audio.js';

const clip = id => ({ id, beats: 4, file: `test/${id}.wav` });
function player() {
  const sent = [];
  const p = new AudioPlayer(() => {}, () => {}, () => {});
  p.context = { decodeAudioData: async () => ({ numberOfChannels: 1, getChannelData: () => new Float32Array(8) }) };
  p.node = { port: { postMessage: data => sent.push(data) } };
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
  assert.ok(fetched.some(path => path.endsWith('/60.wav')));
  assert.ok(fetched.some(path => path.endsWith('/257.wav')));
  assert.deepEqual(sent.filter(item => item.type === 'load').map(item => item.id).sort((a,b) => a-b), [60,257]);
  await p.load([clip(60)], new Set());
  assert.equal(fetched.length, 2);
});

test('failed samples can retry without re-fetching successes; exclusions are read after decoding', async t => {
  const { p, sent } = player();
  const disabled = new Set();
  let fail = true;
  const fetched = [];
  t.mock.method(globalThis, 'fetch', async url => {
    fetched.push(url.pathname);
    if (url.pathname.endsWith('/61.wav') && fail) return { ok: false, status: 503 };
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

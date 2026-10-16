import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { LoopEngine } from '../../Web/engine.js';
import { PadGesture } from '../../Web/gestures.js';

const rate = 48000;
function engine() {
  const e = new LoopEngine(rate);
  for (const [id, beats] of [[0, 4], [1, 8], [2, 16], [30, 4]]) {
    const data = Float32Array.from({ length: rate * beats / 2 }, (_, i) => .5 * Math.sin(2 * Math.PI * 100 * i / rate));
    e.load(id, [data, data], beats);
  }
  return e;
}
function advance(e, seconds) {
  const frames = Math.round(seconds * rate);
  const left = new Float32Array(frames), right = new Float32Array(frames);
  e.render(left, right);
  assert.ok(left.every(Number.isFinite));
  return left;
}

test('a new selection waits for the next four-beat bar', () => {
  const e = engine();
  e.queue([0]);
  advance(e, .75);
  e.queue([1]);
  advance(e, 1.249);
  assert.equal(e.active, 0);
  assert.equal(e.snapshot().pending, true);
  advance(e, .002);
  assert.equal(e.active, 1);
  assert.ok(e.snapshot().progress < .001);
});

test('cycles play each complete 1-, 2- and 4-bar phrase', () => {
  const e = engine();
  e.queue([0, 1, 2]);
  advance(e, 2.001);
  assert.equal(e.active, 1);
  advance(e, 4);
  assert.equal(e.active, 2);
  advance(e, 8);
  assert.equal(e.active, 0);
});

test('the last interaction replaces pending cycles, including across songs', () => {
  const e = engine();
  e.queue([0]);
  advance(e, .5);
  e.queue([1, 2]);
  e.queue([30]);
  advance(e, 1.501);
  assert.equal(e.active, 30);
  assert.deepEqual(e.cycle, [30]);
});

test('tempo slews without jumping phase; boundary follows the integrated beat', () => {
  const e = engine();
  e.queue([2]);
  advance(e, .5);
  const phase = e.snapshot().progress;
  e.setTempo(240);
  assert.equal(e.snapshot().progress, phase);
  advance(e, .01);
  assert.ok(e.bpm > 120 && e.bpm < 150);
  e.queue([30]);
  while (e.beat < 3.99) advance(e, .001);
  assert.equal(e.active, 2);
  advance(e, .01);
  assert.equal(e.active, 30);
  assert.ok(Math.abs(e.startBeat - 4) < 1e-8);
});

test('rate scaling changes the pitch and playback duration together', () => {
  const e = engine();
  e.setTempo(240);
  e.queue([0]);
  const signal = advance(e, .5);
  let crossings = 0;
  for (let i = 1000; i < signal.length - 1; i++) if (signal[i] < 0 && signal[i + 1] >= 0) crossings++;
  const frequency = crossings / ((signal.length - 1000) / rate);
  assert.ok(Math.abs(frequency - 200) < 3, `measured ${frequency} Hz`);
  advance(e, .501);
  assert.ok(e.snapshot().progress < .002);
});

test('exclusions remove queued pads and replace the playing pad at the next bar', () => {
  const e = engine();
  e.queue([0, 1]);
  advance(e, .5);
  e.enable(0, false);
  assert.equal(e.active, 0);
  advance(e, 1.501);
  assert.equal(e.active, 1);
  e.enable(1, false);
  advance(e, 2);
  assert.equal(e.running, false);
  assert.equal(e.active, null);
  assert.ok(advance(e, .02).slice(-128).every(value => value === 0));
  e.queue([0, 1]);
  assert.equal(e.running, false);
  e.enable(0, true);
  e.queue([0]);
  assert.equal(e.active, 0);
});

test('excluding the only pending pad cancels that pending replacement', () => {
  const e = engine();
  e.queue([0]);
  e.queue([1]);
  e.enable(1, false);
  advance(e, 2.1);
  assert.equal(e.active, 0);
  assert.equal(e.running, true);
});

test('stop fades to silence, clears pending launch, and restart starts on a downbeat', () => {
  const e = engine();
  e.queue([0]);
  advance(e, .2);
  e.queue([1]);
  e.stop();
  const beat = e.beat;
  const signal = advance(e, .1);
  assert.equal(e.beat, beat);
  assert.equal(e.pending, null);
  assert.ok(signal.slice(-128).every(value => value === 0));
  e.queue([30]);
  assert.equal(e.beat, 0);
  assert.equal(e.active, 30);
});

test('sample boundaries use short fades instead of discontinuous jumps', () => {
  const e = new LoopEngine(rate);
  e.load(0, [new Float32Array(96000).fill(.8)], 4);
  e.load(1, [new Float32Array(96000).fill(-.8)], 4);
  e.queue([0]);
  advance(e, 1.9);
  e.queue([1]);
  const signal = advance(e, .2);
  let largest = 0;
  for (let i = 1; i < signal.length; i++) largest = Math.max(largest, Math.abs(signal[i] - signal[i - 1]));
  assert.ok(largest < .01, `maximum jump ${largest}`);
});

test('multi-touch, drag and shift-append latch in order; releases do not rewrite', () => {
  const g = new PadGesture();
  assert.deepEqual(g.begin(1, 0), [0]);
  assert.deepEqual(g.begin(2, 1), [0, 1]);
  g.end(1);
  assert.deepEqual(g.move(2, 2), [0, 1, 2]);
  g.end(2);
  assert.deepEqual(g.order, [0, 1, 2]);
  assert.deepEqual(g.begin(3, 30), [30]);
  g.end(3);
  assert.deepEqual(g.begin(4, 0, true, [30]), [30, 0]);
  g.cancel();
  assert.deepEqual(g.begin(5, 1), [1]);
});

test('all catalog samples exist with unique IDs and valid waveform/phrase metadata', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../Samples/catalog.json', import.meta.url)));
  const all = catalog.flatMap(song => song.loops);
  assert.equal(catalog.length, 13);
  assert.equal(all.length, 222);
  assert.ok(catalog.every(song => !['lg', 'ls', 'rr', 'tc', 'dv'].includes(song.id)));
  assert.ok(catalog.find(song => song.id === 'cy').loops.every(sample => sample.bars >= 2));
  assert.deepEqual(catalog.slice(0,2).flatMap(song => song.loops.map(sample => sample.id)), Array.from({length:60}, (_,i) => i));
  assert.equal(new Set(all.map(sample => sample.id)).size, all.length);
  for (const sample of all) {
    assert.ok(existsSync(new URL(`../../Samples/${sample.file}`, import.meta.url)));
    assert.equal(sample.beats, sample.bars * 4);
    assert.ok(sample.waveform.length > 2 && sample.waveform.every(Number.isFinite));
  }
});

test('part masks remove only selected layers, fade to silence, and preserve phrase phase', () => {
  const e = new LoopEngine(rate), frames = rate * 2;
  const frequencies = [180, 600, 2400, 7000];
  const parts = frequencies.map(hz => {
    const a = Float32Array.from({ length: frames }, (_, i) => .1 * Math.sin(2 * Math.PI * hz * i / rate));
    return [a, a];
  });
  // The original and lossy component reconstruction need not match exactly.
  const mix = Float32Array.from({ length: frames }, (_, i) => parts.reduce((sum, part) => sum + part[0][i], 0) + .04 * Math.sin(2 * Math.PI * 1000 * i / rate));
  e.load(42, [mix, mix], 4); e.setParts(42, parts); e.queue([42]); advance(e, .5);
  const before = e.snapshot().progress;
  e.setPartMask(42, 14); advance(e, .1);
  assert.ok(e.snapshot().progress > before);
  const audio = advance(e, 1);
  function amplitude(values, hz) {
    let sin = 0, cos = 0;
    values.forEach((value, i) => { sin += value * Math.sin(2 * Math.PI * hz * i / rate); cos += value * Math.cos(2 * Math.PI * hz * i / rate); });
    return 2 * Math.hypot(sin, cos) / values.length;
  }
  assert.ok(amplitude(audio, 180) < .005);
  assert.ok(amplitude(audio, 600) > .09);
  e.setPartMask(42, 1); advance(e, .1);
  const solo = advance(e, 1);
  assert.ok(amplitude(solo, 180) > .09);
  assert.ok(amplitude(solo, 1000) < .005);
  e.setPartMask(42, 0); advance(e, .1);
  assert.ok(advance(e, .02).every(value => Math.abs(value) < 1e-6));
  e.setPartMask(42, 15); advance(e, .1);
  assert.ok(amplitude(advance(e, 1), 1000) > .035);
});

test('output filters select frequency bands and survive rapid changes', () => {
  function level(mode, hz) {
    const e = new LoopEngine(rate), data = Float32Array.from({length: rate * 2}, (_, i) => .5 * Math.sin(2 * Math.PI * hz * i / rate));
    e.load(1, [data, data], 4); e.setFilter(mode, 1000); e.queue([1]); advance(e, .5);
    const values = advance(e, .25); return Math.sqrt(values.reduce((sum, x) => sum + x*x, 0) / values.length);
  }
  assert.ok(level(1, 200) > level(1, 6000) * 10);
  assert.ok(level(3, 6000) > level(3, 200) * 10);
  assert.ok(level(2, 1000) > level(2, 100) * 4);
  const e = engine(); e.queue([0]);
  for (let i = 0; i < 80; i++) { e.setFilter(i % 4, 40 * (450 ** ((i % 17) / 16))); advance(e, .002); }
});

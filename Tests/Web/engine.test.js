import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { WasmEngine } from '../../Web/wasm-engine.js';
const module = new WebAssembly.Module(readFileSync(new URL('../../Rust/target/wasm32-unknown-unknown/release/breakwater_audio.wasm', import.meta.url)));
class LoopEngine extends WasmEngine {
  constructor(rate) { super(new WebAssembly.Instance(module), rate); }
  get active() { return this.snapshot().active; }
  get beat() { return this.snapshot().beat; }
  get bpm() { return this.snapshot().bpm; }
  get running() { return this.snapshot().playing; }
  get cycle() { return this.snapshot().queue; }
  get pending() { return this.snapshot().pending ? true : null; }
}

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
  assert.ok(e.snapshot().progress < .01);
});

test('nudge changes phase smoothly in either direction and carries through queued loops', () => {
  const ref = engine(), e = engine();
  ref.queue([0]); e.queue([0]); advance(ref, .5); advance(e, .5);
  const before = e.beat;
  e.nudge(10); advance(ref, 1 / rate); advance(e, 1 / rate);
  assert.ok(e.beat - before < .001);
  advance(ref, 1); advance(e, 1);
  assert.ok(Math.abs((e.beat - ref.beat) - .02) < .001);
  assert.equal(e.bpm, 120);
  ref.queue([1]); e.queue([1]); advance(ref, 2); advance(e, 2);
  assert.equal(e.active, 1); assert.equal(ref.active, 1);
  assert.ok(Math.abs((e.beat - ref.beat) - .02) < .001);
  e.nudge(-10); advance(ref, 1); advance(e, 1);
  assert.ok(Math.abs(e.beat - ref.beat) < .001);
  e.nudge(10); e.stop(); advance(e, .01); e.queue([0]); advance(e, .01);
  assert.ok(e.snapshot().progress < .01);
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
  advance(e, 1 / rate);
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
  advance(e, 1 / rate);
  assert.ok(e.beat < .001);
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

test('catalog samples have unique IDs and valid waveform/phrase metadata', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../Samples/catalog.json', import.meta.url)));
  const all = catalog.flatMap(song => song.loops);
  assert.equal(catalog.length, 13);
  assert.equal(all.length, 222);
  assert.ok(catalog.every(song => !['lg', 'ls', 'rr', 'tc', 'dv'].includes(song.id)));
  assert.ok(catalog.find(song => song.id === 'cy').loops.every(sample => sample.bars >= 2));
  assert.deepEqual(catalog.slice(0,2).flatMap(song => song.loops.map(sample => sample.id)), Array.from({length:60}, (_,i) => i));
  assert.equal(new Set(all.map(sample => sample.id)).size, all.length);
  for (const sample of all) {
    assert.ok(!sample.file.startsWith('/') && !sample.file.split('/').includes('..'));
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

test('layered steps repeat the shorter loop, advance after the longest and apply edits at a bar', () => {
  const e = engine();
  e.arrange([{id:0,token:101,step:0,mask:15}, {id:1,token:102,step:0,mask:15}, {id:2,token:103,step:1,mask:15}]);
  advance(e, 2.01);
  assert.deepEqual(e.snapshot().activeTokens, [101,102]);
  assert.ok(e.snapshot().activeProgress[0] < .25, 'shorter loop repeated');
  advance(e, 1.98); assert.deepEqual(e.snapshot().activeTokens, [101,102]);
  advance(e, .02); assert.deepEqual(e.snapshot().activeTokens, [103]);
  e.arrange([{id:0,token:101,step:0,mask:15}, {id:1,token:102,step:1,mask:15}, {id:2,token:103,step:1,mask:15}]);
  advance(e, 1 / rate); assert.equal(e.snapshot().pending, true); advance(e, 2);
  assert.deepEqual(e.snapshot().activeTokens, [102,103]);
  assert.equal(e.snapshot().activeStep, 1);
  e.enable(1, false); advance(e, 2); assert.deepEqual(e.snapshot().activeTokens, [103]);
});

test('editing a future step preserves the current phrase and its end', () => {
  const e = engine();
  e.arrange([{id:1,token:101,step:0,mask:15}]); advance(e, .5);
  e.arrange([{id:1,token:101,step:0,mask:15},{id:0,token:102,step:1,mask:15}]);
  advance(e, 1.51);
  assert.equal(e.snapshot().activeTokens[0], 101);
  assert.ok(e.snapshot().activeProgress[0] > .49);
  advance(e, 2);
  assert.equal(e.snapshot().activeTokens[0], 102);
});

test('two copies of a loop have independent part controls', () => {
  const e = new LoopEngine(rate), frames = rate * 2, frequencies = [180,600,2400,7000];
  const parts = frequencies.map(hz => { const a = Float32Array.from({length:frames}, (_, i) => .1 * Math.sin(2 * Math.PI * hz * i / rate)); return [a, a]; });
  const original = Float32Array.from({length:frames}, (_, i) => parts.reduce((sum, part) => sum + part[0][i], 0));
  e.load(7, [original, original], 4); e.setParts(7, parts);
  e.arrange([{id:7,token:201,step:0,mask:1}, {id:7,token:202,step:0,mask:2}]); advance(e, .2);
  const amp = (audio, hz) => { let a=0,b=0; audio.forEach((x,i) => { a+=x*Math.sin(2*Math.PI*hz*i/rate); b+=x*Math.cos(2*Math.PI*hz*i/rate); }); return 2*Math.hypot(a,b)/audio.length; };
  let audio = advance(e, 1); assert.ok(amp(audio,180) > .045 && amp(audio,600) > .045);
  e.setClipMask(201,0); advance(e,.05); audio=advance(e,1); assert.ok(amp(audio,180) < .003 && amp(audio,600) > .045);
  e.setClipMask(202,0); e.setClipMask(201,1); advance(e,.05); audio=advance(e,1); assert.ok(amp(audio,180) > .045 && amp(audio,600) < .003);
});

test('layered copies keep independent clip filters across live edits and later steps', () => {
  const e = new LoopEngine(rate);
  const data = Float32Array.from({length: rate * 2}, (_, i) => .5 * Math.sin(2 * Math.PI * 6000 * i / rate));
  e.load(7, [data, data], 4);
  const clips = [{id:7,token:201,step:0,mask:15,filterType:1,filterHz:500},
                 {id:7,token:202,step:0,mask:15,filterType:0,filterHz:1200},
                 {id:7,token:203,step:1,mask:15,filterType:1,filterHz:500}];
  e.arrange(clips); advance(e, .15);
  const rms = values => Math.sqrt(values.reduce((sum, value) => sum + value * value, 0) / values.length);
  assert.ok(rms(advance(e, .25)) > .15, 'unfiltered layer remains audible');
  e.setClipMask(202, 0); advance(e, .15);
  assert.ok(rms(advance(e, .25)) < .01, 'low-pass affects only its clip');
  e.setClipFilter(201, 0, 500); advance(e, .15);
  assert.ok(rms(advance(e, .25)) > .15, 'changing the first filter does not restart the phrase');
  e.setClipFilter(203, 3, 500); advance(e, .95);
  assert.deepEqual(e.snapshot().activeTokens, [203]);
  assert.ok(rms(advance(e, .25)) > .3, 'pending step retained its independently edited high-pass');
  e.destroy();
});

test('clip levels are independent, smooth and retained for queued arrangement edits', () => {
  const e = new LoopEngine(rate), data = new Float32Array(rate * 2).fill(.4);
  e.load(7, [data, data], 4);
  const clips = [{id:7,token:201,step:0,mask:15,level:1},
                 {id:7,token:202,step:0,mask:15,level:.25},
                 {id:7,token:203,step:1,mask:15,level:.7}];
  e.arrange(clips); let audio = advance(e, .15);
  assert.ok(Math.abs(audio.at(-1) - .25) < 1e-4, 'initial levels are mixed per instance');
  const before = audio.at(-1);
  e.setClipLevel(201, 0); audio = advance(e, .02);
  assert.ok(Math.abs(audio[0] - before) < .001, 'level updates ramp rather than jump');
  assert.ok(Math.abs(audio.at(-1) - .05) < 1e-4, 'muting one layer leaves the other unchanged');
  clips[0].level = 0;
  e.arrange(clips); // The change to a future step is queued until the next bar.
  e.setClipLevel(203, .3); // Must also update the pending copy, not only the current one.
  advance(e, 2);
  assert.deepEqual(e.snapshot().activeTokens, [203]);
  assert.ok(Math.abs(advance(e, .05).at(-1) - .12) < 1e-4, 'queued clip keeps its edited level');
  e.setClipLevel(203, NaN); advance(e, .03);
  assert.ok(Math.abs(advance(e, .01).at(-1) - .12) < 1e-4, 'non-finite control is ignored');
  e.setClipLevel(203, -1); advance(e, .03);
  assert.ok(Math.abs(advance(e, .01).at(-1)) < 1e-6, 'level is clamped to silence');
  e.destroy();
});

test('legacy filtered clip descriptors still default to unity level', () => {
  const e = new LoopEngine(rate), data = new Float32Array(rate * 2).fill(.4);
  e.load(7, [data, data], 4);
  e.refresh(); e.controlInts.set([7, 201, 0, 15, 0, 1200]);
  e.exports.bw_arrange_with_filters(e.handle, e.control, 1);
  assert.ok(Math.abs(advance(e, .15).at(-1) - .4) < 1e-4);
  e.destroy();
});

test('a short layer crossfades when it wraps underneath a longer one', () => {
  const e = new LoopEngine(rate);
  const short = Float32Array.from({length:rate*2}, (_, i) => i < rate ? .6 : -.6);
  const long = new Float32Array(rate*4);
  e.load(0, [short,short],4); e.load(1,[long,long],8);
  e.arrange([{id:0,token:1,step:0,mask:15},{id:1,token:2,step:0,mask:15}]);
  let previous = advance(e, 1.98).at(-1), jump = 0;
  for (const value of advance(e, .06)) { jump = Math.max(jump, Math.abs(value-previous)); previous=value; }
  assert.ok(jump < .01, `wrap jump ${jump}`);
});

test('Wasm honors a 44.1 kHz audio context and handles changing host block sizes', () => {
  const sr = 44100, e = new LoopEngine(sr), source = new Float32Array(sr * 2).fill(.25);
  e.load(4, [source], 4); e.queue([4]);
  let frames = 0;
  for (const size of [64, 128, 257, 2048, 4097, 73]) {
    const left = new Float32Array(size), right = new Float32Array(size);
    e.render(left, right); frames += size;
    assert.ok(left.every(Number.isFinite));
    assert.deepEqual(left, right);
  }
  assert.equal(e.snapshot().active, 4);
  assert.ok(Math.abs(e.snapshot().beat - frames * 2 / sr) < 1e-8);
  e.destroy();
});

test('eight simultaneous clips keep independent tokens and the ninth is rejected', () => {
  const e = new LoopEngine(rate), data = new Float32Array(rate * 2).fill(.4);
  e.load(0, [data], 4);
  e.arrange(Array.from({ length: 9 }, (_, i) => ({ id: 0, token: i + 1, step: 0, mask: 15 })));
  const audio = advance(e, .1), snapshot = e.snapshot();
  assert.deepEqual(snapshot.activeTokens, [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.ok(Math.abs(audio.at(-1) - .4) < 1e-5, 'layers are averaged for headroom');
  e.destroy();
});

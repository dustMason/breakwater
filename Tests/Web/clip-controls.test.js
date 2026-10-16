import test from 'node:test';
import assert from 'node:assert/strict';
import { filterFromPosition, positionFromFilter, waveformBars } from '../../Web/clip-controls.js';

test('center-detented clip filter sweeps the requested side and round-trips', () => {
  assert.equal(filterFromPosition(0).type, 0);
  assert.equal(filterFromPosition(0.02).type, 0);
  assert.equal(filterFromPosition(-0.02).type, 0);
  assert.equal(filterFromPosition(-1).type, 1);
  assert.equal(filterFromPosition(1).type, 3);
  assert.ok(Math.abs(filterFromPosition(-1).hz - 40) < 1e-9);
  assert.ok(Math.abs(filterFromPosition(1).hz - 18000) < 1e-8);
  for (const position of [-1, -0.8, -0.3, 0.3, 0.8, 1]) {
    const { type, hz } = filterFromPosition(position);
    assert.ok(Math.abs(positionFromFilter(type, hz) - position) < 1e-9);
  }
  assert.ok(filterFromPosition(-0.2).hz > filterFromPosition(-0.8).hz);
  assert.ok(filterFromPosition(0.2).hz < filterFromPosition(0.8).hz);
  assert.equal(filterFromPosition(NaN).type, 0);
});

test('stylized waveform reflects each clip part mask and retains a ghost of the original', () => {
  const original = [0.8, 0.4];
  const parts = [[0.3, 0.2], [0.4, 0.1], [0.2, 0.1], [0.1, 0.2]];
  assert.deepEqual(waveformBars(original, parts, 15, 2).map(b => b.enabled), original);
  assert.deepEqual(waveformBars(original, parts, 0, 2), [{ full: 0.8, enabled: 0 }, { full: 0.4, enabled: 0 }]);
  assert.deepEqual(waveformBars(original, parts, 1, 2).map(b => b.enabled), [0.3, 0.2]);
  assert.ok(Math.abs(waveformBars(original, parts, 3, 2)[0].enabled - 0.5) < 1e-9);
});

test('clip waveforms use the same number of bars for different envelope sizes', () => {
  for (const length of [8, 64, 256]) {
    const envelope = Array.from({ length }, (_, index) => index / length);
    const bars = waveformBars(envelope, null, 15);
    assert.equal(bars.length, 32);
    assert.equal(bars[0].full, 0);
    assert.ok(bars.at(-1).full > 0.8);
  }
});

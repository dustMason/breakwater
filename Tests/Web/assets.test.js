import test from 'node:test';
import assert from 'node:assert/strict';
import { assetBase, assetURL } from '../../Web/assets.js';

test('asset addresses are HTTPS and cannot escape the configured library', () => {
  const base = assetBase('https://assets.example.invalid/music', 'https://player.example.invalid/');
  assert.equal(base.href, 'https://assets.example.invalid/music/');
  assert.equal(assetURL(base, 'catalog.json').href, base.href + 'catalog.json');
  assert.equal(assetURL(base, `objects/${'a'.repeat(64)}.wav`).origin, base.origin);
  for (const path of ['../other', '/catalog.json', 'objects/abc.wav', 'https://evil.invalid/file']) {
    assert.throws(() => assetURL(base, path));
  }
  assert.throws(() => assetBase('http://example.invalid/', base));
  assert.throws(() => assetBase('https://u:p@example.invalid/', base));
  assert.throws(() => assetBase('https://example.invalid/?token=x', base));
  assert.equal(assetBase('./local-assets/', 'http://localhost:8765/').href, 'http://localhost:8765/local-assets/');
});

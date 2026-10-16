#!/usr/bin/env python3
"""Prevent partial migrations, stale catalog overwrites and invalid cache reuse."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / 'Scripts/separate_parts.py'
spec = importlib.util.spec_from_file_location('separate_parts', script)
parts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parts)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = [{'name': 'One', 'partLabels': ['Low', 'Body', 'Attack', 'High'],
                         'loops': [{'id': 0, 'file': 'one.wav'}, {'id': 1, 'file': 'two.wav'}]},
                        {'name': 'Two', 'partLabels': ['Low', 'Body', 'Attack', 'High'],
                         'loops': [{'id': 2, 'file': 'three.wav'}]}]
        self.path = self.root / 'catalog.json'
        self.original = json.dumps(self.catalog).encode()
        self.path.write_bytes(self.original)
        (self.root / 'one.wav').write_bytes(b'original source')
        self.hashes = {'one.wav': parts.digest(self.root / 'one.wav')}

    def test_first_migration_cannot_mislabel_unprocessed_loops(self):
        with self.assertRaisesRegex(ValueError, 'every loop'):
            parts.select_samples(self.catalog, [0])
        self.assertEqual([s['id'] for s in parts.select_samples(self.catalog, [0, 1])], [0, 1])
        self.catalog[0]['partLabels'] = list(parts.PARTS)
        self.assertEqual([s['id'] for s in parts.select_samples(self.catalog, [0])], [0])

    def test_reject_unknown_empty_and_duplicate_ids(self):
        for ids in ([99], []):
            with self.assertRaises(ValueError):
                parts.select_samples(self.catalog, ids)
        self.catalog[1]['loops'][0]['id'] = 0
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            parts.select_samples(self.catalog, None)

    def test_concurrent_curation_is_not_overwritten(self):
        new = self.original + b'\n'
        self.path.write_bytes(new)
        with self.assertRaisesRegex(RuntimeError, 'Catalog changed'):
            parts.publish_catalog(self.path, self.original, copy.deepcopy(self.catalog), {0: {}}, self.root, self.hashes)
        self.assertEqual(self.path.read_bytes(), new)

    def test_changed_source_does_not_publish_stale_parts(self):
        (self.root / 'one.wav').write_bytes(b'curated new source')
        with self.assertRaisesRegex(RuntimeError, 'Source changed'):
            parts.publish_catalog(self.path, self.original, copy.deepcopy(self.catalog), {0: {}}, self.root, self.hashes)
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_whole_song_publish_preserves_other_songs_and_original_metadata(self):
        parts.publish_catalog(self.path, self.original, copy.deepcopy(self.catalog), {0: {'files': []}, 1: {'files': []}}, self.root, self.hashes)
        result = json.loads(self.path.read_bytes())
        self.assertEqual(result[0]['partLabels'], list(parts.PARTS))
        self.assertEqual(result[1], self.catalog[1])
        self.assertEqual(result[0]['loops'][0]['file'], 'one.wav')
        self.assertEqual((self.root / 'one.wav').read_bytes(), b'original source')

    def test_cache_requires_matching_source_and_all_encoded_hashes(self):
        files=[]
        for i in range(4):
            f = self.root / f'{i}.m4a'; f.write_bytes(bytes([i])); files.append(f.name)
        sample = {'id': 0, 'waveform': [0] * 100, 'parts': {'files': files, 'waveforms': [[0] * 100] * 4,
                  'separation': {'recipe': parts.RECIPE, 'sourceSHA256': 'source',
                                 'fileSHA256': [parts.digest(self.root / f) for f in files]}}}
        self.assertIsNotNone(parts.cached_parts(self.root, sample, 'source'))
        parts.write_receipt(self.root, sample, sample['parts'])
        # A batch that never published the catalog can recover a completed loop.
        without_parts = dict(sample); del without_parts['parts']
        self.assertEqual(parts.read_receipt(self.root, without_parts, 'source'), sample['parts'])
        self.assertIsNone(parts.cached_parts(self.root, sample, 'changed'))
        (self.root / files[2]).write_bytes(b'truncated')
        self.assertIsNone(parts.cached_parts(self.root, sample, 'source'))
        self.assertIsNone(parts.read_receipt(self.root, without_parts, 'source'))


if __name__ == '__main__':
    unittest.main()

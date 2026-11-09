#!/usr/bin/env python3
# Synthetic DEX headers exercise packaging checks, not bytecode execution.
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('preview_packager', ROOT/'tools/package.py')
pkg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pkg)

class Package(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        for name in pkg.FILES:
            p = self.d/'module'/name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('fixture\n')
        self.prop = self.d/'module/module.prop'
        self.prop.write_text('id=OnePlus15-165HZ-LTPO\nname=Preview\nversion=v1.9.0-preview.1\nversionCode=10901\nauthor=Test\ndescription=Test\n')
        (self.d/'LICENSE').write_text('license fixture')
        (self.d/'docs').mkdir(); (self.d/'docs/preview-build.md').write_text('preview fixture')
        dex = bytearray(144); dex[:8] = b'dex\n035\x00'
        struct.pack_into('<III', dex, 32, len(dex), 112, 0x12345678)
        struct.pack_into('<II', dex, 96, 1, 112)
        dex[12:32] = hashlib.sha1(dex[32:]).digest()
        struct.pack_into('<I', dex, 8, zlib.adler32(dex[12:]) & 0xffffffff)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as jar: jar.writestr('classes.dex', dex)
        self.jar = self.d/'module/bin/xmlguard.jar'; self.jar.write_bytes(buffer.getvalue())
    def tearDown(self): self.tmp.cleanup()
    def create(self): return pkg.create(self.d, 'a'*40)
    def test_allowlist_manifest_and_permissions(self):
        (self.d/'module/vrrd.log').write_text('private log')
        (self.d/'module/stop').touch()
        out = self.create()
        with zipfile.ZipFile(out) as z:
            self.assertNotIn('vrrd.log', z.namelist()); self.assertNotIn('stop', z.namelist())
            manifest = json.loads(z.read('BUILD-MANIFEST.json'))
            self.assertEqual(manifest['source_revision'], 'a'*40)
            for name, digest in manifest['sha256'].items():
                self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(), digest)
            self.assertEqual((z.getinfo('bin/xmlguard.jar').external_attr >> 16) & 0o777, 0o444)
            self.assertEqual((z.getinfo('service.sh').external_attr >> 16) & 0o777, 0o755)
    def test_missing_jar(self):
        self.jar.unlink()
        with self.assertRaises(ValueError): self.create()
    def test_invalid_jar(self):
        self.jar.write_text('not a jar')
        with self.assertRaises((ValueError, zipfile.BadZipFile)): self.create()
    def test_corrupt_dex(self):
        with zipfile.ZipFile(self.jar) as z: dex = bytearray(z.read('classes.dex'))
        dex[-1] ^= 1
        with zipfile.ZipFile(self.jar, 'w') as z: z.writestr('classes.dex', dex)
        with self.assertRaises(ValueError): self.create()
    def test_upstream_update_url_rejected(self):
        with self.prop.open('a') as f: f.write('updateJson=https://example.invalid/update.json\n')
        with self.assertRaises(ValueError): self.create()
    def test_low_version_code_rejected(self):
        self.prop.write_text(self.prop.read_text().replace('10901', '10800'))
        with self.assertRaises(ValueError): self.create()
    def test_symlink_rejected(self):
        p = self.d/'module/service.sh'; p.unlink(); p.symlink_to(self.d/'LICENSE')
        with self.assertRaises(ValueError): self.create()
    def test_existing_zip_not_overwritten(self):
        out = self.create(); before = out.read_bytes()
        with self.assertRaises(ValueError): self.create()
        self.assertEqual(out.read_bytes(), before)
    def test_duplicate_property_rejected(self):
        with self.prop.open('a') as f: f.write('id=other\n')
        with self.assertRaises(ValueError): self.create()

if __name__ == '__main__': unittest.main()

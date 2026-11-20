#!/usr/bin/env python3
# Runs on a host/Termux JDK. Android app_process must be checked separately.
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '<refresh_rate_config version="20260601"><config defaultRateId="1-1-2-3"/><item package="com.example.app" rateId="1-1-2-3"/><other flag="keep"/></refresh_rate_config>'
PATCHED = SOURCE.replace('20260601', '20991231').replace('<config ', '<config defaultMaxRate="165" ').replace('1-1-2-3', '1-3-2-7')

class Guard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.d = Path(cls.tmp.name)
        subprocess.run(['javac', '--release', '8', '-d', str(cls.d), str(ROOT/'tools/XmlGuard.java')], check=True)
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def check(self, text, valid=False):
        f = self.d/'check.xml'
        f.write_bytes(text if isinstance(text, bytes) else text.encode('utf-8'))
        r = subprocess.run(['java', '-cp', str(self.d), 'XmlGuard', 'check', str(f)], capture_output=True, text=True, timeout=10)
        self.assertEqual(r.returncode == 0, valid, r.stdout+r.stderr)
    def compare(self, text, valid=False):
        a,b = self.d/'before.xml', self.d/'after.xml'
        a.write_text(SOURCE); b.write_text(text)
        r = subprocess.run(['java', '-cp', str(self.d), 'XmlGuard', 'compare', str(a), str(b)], capture_output=True, text=True, timeout=10)
        self.assertEqual(r.returncode == 0, valid, r.stdout+r.stderr)
    def test_valid_source(self): self.check(SOURCE, True)
    def test_duplicate_attribute(self): self.check(SOURCE.replace('<config ', '<config defaultRateId="1-1-2-3" '))
    def test_broken_structure(self): self.check(SOURCE.replace('</refresh_rate_config>', '</wrong>'))
    def test_dtd(self): self.check('<!DOCTYPE refresh_rate_config [<!ENTITY x SYSTEM "file:///etc/passwd">]>'+SOURCE)
    def test_invalid_utf8(self): self.check(b'\xff'+SOURCE.encode())
    def test_utf16(self): self.check(SOURCE.encode('utf-16'))
    def test_wrong_root(self): self.check(SOURCE.replace('refresh_rate_config','other_root'))
    def test_two_configs(self): self.check(SOURCE.replace('<config ', '<config defaultRateId="1-1-2-3"/><config '))
    def test_invalid_rate(self): self.check(SOURCE.replace('rateId="1-1-2-3"','rateId="oops"'))
    def test_valid_patch(self): self.compare(PATCHED, True)
    def test_deleted_item(self): self.compare(PATCHED.replace('<item package="com.example.app" rateId="1-3-2-7"/>',''))
    def test_changed_other_tag(self): self.compare(PATCHED.replace('flag="keep"','flag="lost"'))
    def test_added_unknown_tag(self): self.compare(PATCHED.replace('</refresh_rate_config>','<unexpected/></refresh_rate_config>'))
    def test_invalid_added_package(self): self.compare(PATCHED.replace('</refresh_rate_config>','<cameraOverride package="bad/name"/></refresh_rate_config>'))
    def test_valid_camera_addition(self): self.compare(PATCHED.replace('</refresh_rate_config>','<cameraOverride package="com.example.camera"/></refresh_rate_config>'), True)
    def test_missing_max_rate(self): self.compare(PATCHED.replace('defaultMaxRate="165" ',''))
    def test_changed_root_attribute(self): self.compare(PATCHED.replace('<refresh_rate_config ', '<refresh_rate_config unexpected="true" '))
    def test_no_high_rate(self): self.compare(PATCHED.replace('rateId="1-3-2-7"', 'rateId="1-1-2-3"'))

if __name__ == '__main__': unittest.main()

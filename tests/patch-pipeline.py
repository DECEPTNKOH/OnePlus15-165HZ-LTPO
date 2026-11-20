#!/usr/bin/env python3
# Real shell/sed pipeline; XML guard and privileged commands are test doubles.
# This suite does not substitute for tests/xmlguard.py or Android parser checks.
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''<refresh_rate_config version="20260601">
<config defaultRateId="1-1-2-3" />
<item package="com.example.camera" rateId="1-1-2-3" />
<item package="comXexampleXcamera" rateId="1-1-2-3" />
<item package="com.example.video" rateId="2-2-2-2" />
</refresh_rate_config>
'''
VALIDATOR = r'''
import os, sys, xml.etree.ElementTree as ET
with open(os.environ['EVENTS'], 'a') as f: f.write('GUARD\n')
if os.environ.get('GUARD_FAIL'): sys.exit(1)
a, b = ET.parse(sys.argv[2]).getroot(), ET.parse(sys.argv[3]).getroot()
assert a.tag == b.tag == 'refresh_rate_config'
assert len(a.findall('config')) == len(b.findall('config')) == 1
assert b.attrib['version'] == '20991231'
assert b.find('config').attrib['defaultMaxRate'] == '165'
for e in a.findall('item'):
    assert any(x.attrib['package'] == e.attrib['package'] for x in b.findall('item'))
'''

class Pipeline(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        self.m = self.d/'module'; self.m.mkdir()
        (self.m/'sed').mkdir(); (self.m/'bin').mkdir()
        (self.m/'bin/xmlguard.jar').write_text('test placeholder')
        self.stock = self.d/'stock'; self.stock.mkdir()
        self.xml = self.stock/'refresh_rate_config.xml'; self.xml.write_text(SOURCE)
        code = (ROOT/'module/post-fs-data.sh').read_text().replace(
            'for p in /my_product/etc /my_stock/etc /product/etc /system/etc /vendor/etc; do',
            f'for p in "{self.stock}"; do')
        (self.m/'post-fs-data.sh').write_text(code)
        for name in ('force.sed','respect.sed'):
            shutil.copyfile(ROOT/'module/sed'/name, self.m/'sed'/name)
        (self.m/'mock-validator.py').write_text(VALIDATOR)
        (self.m/'xmlguard.sh').write_text('exec "$PYTHON" "${0%/*}/mock-validator.py" "$@"\n')
        self.bin = self.d/'bin'; self.bin.mkdir()
        scripts = {
            'chown': 'exit 0',
            'chcon': '[ -z "$CHCON_FAIL" ]',
            'ls': 'echo "u:object_r:system_file:s0 test"',
            'mount': 'echo MOUNT >> "$EVENTS"; [ -z "$MOUNT_FAIL" ]',
            'umount': 'echo UMOUNT >> "$EVENTS"',
            'sed': '''
case "$*" in
  *force.sed*|*respect.sed*) [ -z "$MAIN_SED_FAIL" ] || exit 1 ;;
  *pkg.sed*) [ -z "$PKG_SED_FAIL" ] || exit 1 ;;
esac
exec "$REAL_SED" "$@"
''',
        }
        for name, body in scripts.items():
            p = self.bin/name; p.write_text('#!/bin/sh\n'+body+'\n'); p.chmod(0o755)
        self.events = self.d/'events'
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        EVENTS=str(self.events), PYTHON=sys.executable, REAL_SED=shutil.which('sed'))
        self.config()
    def tearDown(self): self.tmp.cleanup()
    def config(self, extra=''):
        (self.m/'vrr.conf').write_text('FORCE_ALL=1\nCAMERA_165=1\nWIN_OVERRIDE=camera\nCAMERA_PKGS="com.example.camera"\n'
            + f'CAMERA_LIST="{self.d}/none"\nCAMERA_USED="{self.d}/used"\n' + extra)
    def run_patch(self, success=True):
        r = subprocess.run(['sh', str(self.m/'post-fs-data.sh')], env=self.env,
                           capture_output=True, text=True, timeout=10)
        log = (self.m/'vrrd.log').read_text()
        self.assertEqual(r.returncode == 0, success, r.stdout+r.stderr+log)
        self.assertEqual((self.m/'.mounted').exists(), success, log)
        if not success:
            self.assertNotIn('MOUNT', self.events.read_text() if self.events.exists() else '')
        return log
    def test_success_guard_before_mount(self):
        self.run_patch()
        self.assertEqual(self.events.read_text().splitlines(), ['GUARD','MOUNT'])
    def test_respect_mode(self):
        self.config('FORCE_ALL=0\n'); self.run_patch()
        doc = ET.parse(self.m/'patched/refresh_rate_config.xml').getroot()
        self.assertEqual(doc.find("item[@package='com.example.video']").attrib['rateId'], '2-2-2-2')
    def test_missing_jar(self):
        (self.m/'bin/xmlguard.jar').unlink(); self.run_patch(False)
    def test_invalid_xml(self):
        self.xml.write_text(SOURCE.replace('</refresh_rate_config>', '</wrong>')); self.run_patch(False)
    def test_duplicate_attribute(self):
        self.xml.write_text(SOURCE.replace('<config ', '<config defaultRateId="1-1-2-3" ')); self.run_patch(False)
    def test_guard_failure(self):
        self.env['GUARD_FAIL']='1'; self.run_patch(False)
    def test_primary_sed_failure(self):
        self.env['MAIN_SED_FAIL']='1'; self.run_patch(False)
    def test_camera_sed_failure(self):
        self.env['PKG_SED_FAIL']='1'; self.run_patch(False)
    def test_invalid_package(self):
        self.config('CAMERA_PKGS="com.bad|oops"\n'); self.run_patch(False)
    def test_package_is_not_regex(self):
        self.run_patch()
        doc = ET.parse(self.m/'patched/refresh_rate_config.xml').getroot()
        self.assertEqual(doc.find("item[@package='com.example.camera']").attrib['enableWinOverride'], 'false')
        self.assertNotIn('enableWinOverride', doc.find("item[@package='comXexampleXcamera']").attrib)
    def test_missing_insertion_anchor(self):
        self.xml.write_text(SOURCE.replace('<config defaultRateId="1-1-2-3" />', '<config defaultRateId="1-1-2-3"></config>'))
        self.run_patch(False)
    def test_comment_in_list(self):
        (self.m/'camera_pkgs.default').write_text('# comment\ncom.example.other # note\n')
        self.run_patch()
    def test_selinux_failure(self):
        self.env['CHCON_FAIL']='1'; self.run_patch(False)
    def test_already_patched_not_claimed(self):
        self.xml.write_text(SOURCE.replace('20260601','20991231')); self.run_patch(False)
    def test_mount_failure_no_marker(self):
        self.env['MOUNT_FAIL']='1'
        r = subprocess.run(['sh', str(self.m/'post-fs-data.sh')], env=self.env, timeout=10)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.m/'.mounted').exists())
        self.assertEqual(self.events.read_text().splitlines(), ['GUARD','MOUNT','MOUNT'])

if __name__ == '__main__': unittest.main()

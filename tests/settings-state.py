#!/usr/bin/env python3
# Run: python3 tests/settings-state.py. All settings commands are mocked.
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / "module" / "settings-state.sh"
MOCK = r'''
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STORE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
if a == ['activity', 'get-current-user']:
    print(s.get('current_user', 0)); sys.exit(0)
if a and a[0] == 'settings': a = a[1:]
if len(a) < 5 or a[0] != '--user': sys.exit(2)
u, op = a[1], a[2]
if s.get('fail'): sys.exit(1)
if op == 'get':
    print(s.get(u, 'null'))
elif op in ('put', 'delete'):
    if not s.get('ignore_writes'):
        if op == 'put': s[u] = a[5]
        else: s.pop(u, None)
    s['writes'] = s.get('writes', 0) + 1
    p.write_text(json.dumps(s))
else: sys.exit(2)
'''

class SettingsState(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        (self.d / 'bin').mkdir()
        self.store = self.d / 'store.json'
        self.set_store({'0': '7'})
        for name in ('cmd', 'settings', 'am'):
            p = self.d / 'bin' / name
            p.write_text('#!' + sys.executable + '\n' + MOCK)
            p.chmod(0o755)
        self.env = dict(os.environ, MOCK_STORE=str(self.store),
                        VRR_STATE_DIR=str(self.d / 'state'),
                        PATH=str(self.d / 'bin') + os.pathsep + os.environ['PATH'])
    def tearDown(self): self.tmp.cleanup()
    def set_store(self, data): self.store.write_text(json.dumps(data))
    def read_store(self): return json.loads(self.store.read_text())
    def run_shell(self, body):
        result = subprocess.run(['sh', '-c', '. "$1"\n' + body, 'sh', str(LIB)],
                                env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    def test_value_restored(self):
        self.run_shell('vrr_baseline_prepare && vrr_mode_write 1 && vrr_baseline_restore')
        self.assertEqual(self.read_store()['0'], '7')
    def test_absent_key_deleted(self):
        self.set_store({})
        self.run_shell('vrr_baseline_prepare && vrr_mode_write 1 && vrr_baseline_restore')
        self.assertNotIn('0', self.read_store())
    def test_restart_does_not_overwrite_snapshot(self):
        self.run_shell('vrr_baseline_prepare && vrr_mode_write 1')
        self.run_shell('vrr_baseline_prepare && vrr_baseline_restore')
        self.assertEqual(self.read_store()['0'], '7')
    def test_read_failure_prevents_writes(self):
        self.set_store({'0': '7', 'fail': True})
        self.run_shell('if vrr_baseline_prepare; then exit 10; fi\nif vrr_mode_write 1; then exit 11; fi')
        self.assertFalse((self.d / 'state' / 'baseline').exists())
        self.assertNotIn('writes', self.read_store())
    def test_corrupt_snapshot_rejected(self):
        (self.d / 'state').mkdir()
        (self.d / 'state' / 'baseline').write_text('v1\n0\n$(touch injected)\nobserved-before-first-write\n')
        self.run_shell('if vrr_baseline_prepare; then exit 10; fi\nif vrr_mode_write 1; then exit 11; fi')
        self.assertNotIn('writes', self.read_store())
    def test_restore_uses_saved_user(self):
        self.run_shell('vrr_baseline_prepare && vrr_mode_write 1')
        self.set_store({'0': '1', '10': '3', 'current_user': 10})
        self.run_shell('vrr_baseline_restore')
        self.assertEqual(self.read_store()['0'], '7')
        self.assertEqual(self.read_store()['10'], '3')
    def test_restore_readback_failure_retains_snapshot(self):
        self.run_shell('vrr_baseline_prepare')
        self.set_store({'0': '1', 'ignore_writes': True})
        self.run_shell('if vrr_baseline_restore; then exit 10; fi')
        self.assertTrue((self.d / 'state' / 'baseline').exists())
    def test_write_without_snapshot_rejected(self):
        self.run_shell('if vrr_mode_write 1; then exit 10; fi')
        self.assertNotIn('writes', self.read_store())

if __name__ == '__main__': unittest.main()

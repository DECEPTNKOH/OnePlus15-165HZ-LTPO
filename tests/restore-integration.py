#!/usr/bin/env python3
# Host-only daemon/uninstall integration tests. No real Android settings used.
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'module'
MOCK = r'''
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STORE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
if a == ['activity', 'get-current-user']:
    print(0); sys.exit(0)
if a and a[0] == 'settings': a = a[1:]
if len(a) < 5 or a[:2] != ['--user', '0']: sys.exit(2)
if a[3:5] != ['secure', 'oplus_customize_screen_refresh_rate']: sys.exit(2)
op = a[2]
if s.get('fail'): sys.exit(1)
if op == 'get': print(s.get('value', 'null'))
elif op in ('put', 'delete'):
    if s.get('fail_restore') and (op == 'delete' or a[5] == '3'): sys.exit(1)
    if op == 'delete': s.pop('value', None)
    else: s['value'] = a[5]
    s['writes'] = s.get('writes', 0) + 1
    p.write_text(json.dumps(s))
else: sys.exit(2)
'''

class RestoreIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        (self.d / 'bin').mkdir()
        self.store = self.d / 'store.json'
        self.store.write_text(json.dumps({'value': '3'}))
        self.children = []
        for name in ('lifecycle.sh', 'settings-state.sh', 'uninstall.sh'):
            (self.d / name).write_bytes((MODULE / name).read_bytes())
        self.dev = self.d / 'fake-input'; self.dev.touch()
        source = (MODULE / 'vrrd.sh').read_text().replace(
            'for d in /dev/input/event*; do', f'for d in "{self.dev}"; do')
        (self.d / 'vrrd.sh').write_text(source)
        (self.d / 'vrr.conf').write_text("IDLE_TIMEOUT=0.1\nKEEP_ACTIVE_CAMERA=0\nKEEP_ACTIVE_PKGS=''\nDEBUG=1\n")
        for name in ('cmd', 'settings', 'am'):
            p = self.d / 'bin' / name
            p.write_text('#!' + sys.executable + '\n' + MOCK); p.chmod(0o755)
        p = self.d / 'bin' / 'getevent'
        p.write_text('#!/bin/sh\nif [ "$1" = -pl ]; then echo ABS_MT_POSITION_X; else exec sleep 30; fi\n')
        p.chmod(0o755)
        self.env = dict(os.environ, MOCK_STORE=str(self.store),
                        VRR_STATE_DIR=str(self.d / 'state'),
                        PATH=str(self.d / 'bin') + os.pathsep + os.environ['PATH'])
    def tearDown(self):
        for p in self.children:
            if p.poll() is None: p.kill()
            p.wait(timeout=5)
        self.tmp.cleanup()
    def data(self): return json.loads(self.store.read_text())
    def start(self):
        p = subprocess.Popen(['sh', str(self.d / 'vrrd.sh')], env=self.env)
        self.children.append(p)
        return p
    def idle(self, p, min_writes=0):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            self.assertIsNone(p.poll(), 'daemon exited before idle')
            data = self.data()
            if data.get('value') == '1' and data.get('writes', 0) >= min_writes: return
            time.sleep(0.02)
        self.fail('idle timeout')
    def stop(self, p):
        (self.d / 'stop').touch()
        return p.wait(timeout=6)
    def uninstall(self):
        return subprocess.run(['sh', str(self.d / 'uninstall.sh')], env=self.env,
                              capture_output=True, text=True, timeout=20).returncode
    def test_stop_restores_value_and_keeps_snapshot(self):
        p = self.start(); self.idle(p)
        self.assertEqual(self.stop(p), 0)
        self.assertEqual(self.data()['value'], '3')
        self.assertTrue((self.d / 'state' / 'baseline').exists())
        self.assertFalse((self.d / '.vrrd.pid').exists())
    def test_stop_deletes_originally_absent_key(self):
        self.store.write_text('{}')
        p = self.start(); self.idle(p)
        self.assertEqual(self.stop(p), 0)
        self.assertNotIn('value', self.data())
    def test_sigterm_restores(self):
        p = self.start(); self.idle(p)
        p.terminate()
        self.assertEqual(p.wait(timeout=6), 0)
        self.assertEqual(self.data()['value'], '3')
    def test_uninstall_stops_daemon_and_retires_snapshot(self):
        p = self.start(); self.idle(p)
        self.assertEqual(self.uninstall(), 0)
        self.assertEqual(p.wait(timeout=6), 0)
        self.assertEqual(self.data()['value'], '3')
        self.assertFalse((self.d / 'state' / 'baseline').exists())
    def test_uninstall_without_snapshot_does_not_signal_legacy_pid(self):
        other = subprocess.Popen(['sleep', '30']); self.children.append(other)
        (self.d / '.vrrd.pid').write_text(str(other.pid))
        self.assertEqual(self.uninstall(), 0)
        self.assertIsNone(other.poll())
        self.assertNotIn('writes', self.data())
    def test_snapshot_failure_blocks_switching(self):
        self.store.write_text(json.dumps({'value': '3', 'fail': True}))
        p = self.start()
        self.assertEqual(p.wait(timeout=6), 1)
        self.assertNotIn('writes', self.data())
        self.assertFalse((self.d / 'state' / 'baseline').exists())
    def test_restore_failure_retains_snapshot(self):
        p = self.start(); self.idle(p)
        data = self.data(); data['fail_restore'] = True
        self.store.write_text(json.dumps(data))
        self.assertEqual(self.stop(p), 1)
        self.assertTrue((self.d / 'state' / 'baseline').exists())
    def test_sigkill_restart_preserves_first_baseline(self):
        p = self.start(); self.idle(p)
        p.kill(); p.wait(timeout=5)
        writes = self.data().get('writes', 0)
        q = self.start(); self.idle(q, min_writes=writes + 2)
        self.assertEqual(self.stop(q), 0)
        self.assertEqual(self.data()['value'], '3')

if __name__ == '__main__': unittest.main()

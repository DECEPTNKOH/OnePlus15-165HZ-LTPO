#!/usr/bin/env python3
"""Host regression tests: python3 tests/lifecycle.py. No Android/root writes."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

LIB = Path(__file__).resolve().parents[1] / "module" / "lifecycle.sh"

class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        self.children = []
        (self.d / "lifecycle.sh").write_bytes(LIB.read_bytes())
        (self.d / "runner.sh").write_text('''
MODDIR=${0%/*}
PIDFILE="$MODDIR/.vrrd.pid"
say() { echo "$*" >> "$MODDIR/log"; }
. "$MODDIR/lifecycle.sh"
vrr_acquire
rc=$?
[ "$rc" = 0 ] || exit "$rc"
trap 'exit 0' TERM INT HUP
: > "$MODDIR/ready.$$"
while :; do sleep 0.05 9>&-; done
''')
    def tearDown(self):
        for p in self.children:
            if p.poll() is None:
                p.terminate()
            p.wait(timeout=5)
        self.tmp.cleanup()
    def start(self):
        p = subprocess.Popen(["sh", str(self.d / "runner.sh")])
        self.children.append(p)
        return p
    def ready(self, p):
        end = time.monotonic() + 3
        while time.monotonic() < end:
            if (self.d / f"ready.{p.pid}").exists(): return
            if p.poll() is not None: self.fail(f"startup failed: {p.returncode}")
            time.sleep(0.01)
        self.fail("startup timeout")
    def test_unrelated_live_pid(self):
        other = subprocess.Popen(["sleep", "30"])
        self.children.append(other)
        (self.d / ".vrrd.pid").write_text(str(other.pid))
        p = self.start(); self.ready(p)
        self.assertIsNone(other.poll())
        self.assertEqual((self.d / ".vrrd.pid").read_text().strip(), str(p.pid))
    def test_stale_boot_metadata(self):
        (self.d / ".vrrd.identity").write_text("11953 previous-boot 1\n")
        p = self.start(); self.ready(p)
        token = (self.d / ".vrrd.identity").read_text().split()
        self.assertEqual(token[0], str(p.pid))
        self.assertEqual(token[1], Path("/proc/sys/kernel/random/boot_id").read_text().strip())
        self.assertTrue(token[2].isdigit())
    def test_parallel_start_and_nonowner_cleanup(self):
        a, b = self.start(), self.start()
        end = time.monotonic() + 3
        while time.monotonic() < end and a.poll() is None and b.poll() is None:
            time.sleep(0.01)
        live = [p for p in (a, b) if p.poll() is None]
        self.assertEqual(len(live), 1)
        self.ready(live[0])
        self.assertEqual((self.d / ".vrrd.pid").read_text().strip(), str(live[0].pid))
    def test_normal_exit_cleans_metadata_not_lock_inode(self):
        p = self.start(); self.ready(p)
        inode = (self.d / ".vrrd.lock").stat().st_ino
        p.terminate(); p.wait(timeout=5)
        self.assertFalse((self.d / ".vrrd.pid").exists())
        self.assertFalse((self.d / ".vrrd.identity").exists())
        self.assertEqual((self.d / ".vrrd.lock").stat().st_ino, inode)
        q = self.start(); self.ready(q)
    def test_sigkill_restart(self):
        p = self.start(); self.ready(p)
        os.kill(p.pid, signal.SIGKILL); p.wait(timeout=5)
        q = self.start(); self.ready(q)
        self.assertEqual((self.d / ".vrrd.pid").read_text().strip(), str(q.pid))


class DaemonIntegration(unittest.TestCase):
    def test_setting_failure_does_not_commit_state(self):
        text = (LIB.parent / "vrrd.sh").read_text()
        function = text.split('set_state() {', 1)[1].split('\nCHILD=', 1)[0]
        script = '''
state=active
ACTIVE_MODE=7
IDLE_MODE=1
camera_in_use() { return 1; }
keep_active_pkg() { return 1; }
log() { :; }
say() { :; }
put_mode() { return 1; }
set_state() {''' + function + '''
set_state idle && exit 10
[ "$state" = active ] || exit 11
put_mode() { return 0; }
set_state idle || exit 12
[ "$state" = idle ] || exit 13
'''
        self.assertEqual(subprocess.run(["sh", "-c", script]).returncode, 0)
    def test_remove_flag_observed_while_idle(self):
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            (d / "bin").mkdir()
            (d / "lifecycle.sh").write_bytes(LIB.read_bytes())
            dev = d / "fake-input"; dev.touch()
            source = (LIB.parent / "vrrd.sh").read_text()
            source = source.replace('for d in /dev/input/event*; do', f'for d in "{dev}"; do')
            (d / "vrrd.sh").write_text(source)
            (d / "vrr.conf").write_text("IDLE_TIMEOUT=0.1\nKEEP_ACTIVE_CAMERA=0\nKEEP_ACTIVE_PKGS=''\nDEBUG=1\n")
            (d / "bin" / "getevent").write_text('#!/bin/sh\nif [ "$1" = -pl ]; then echo ABS_MT_POSITION_X; else exec sleep 30; fi\n')
            (d / "bin" / "cmd").write_text('#!/bin/sh\nexit 0\n')
            for f in (d / "bin").iterdir(): f.chmod(0o755)
            env = dict(os.environ, PATH=str(d / "bin") + os.pathsep + os.environ["PATH"])
            p = subprocess.Popen(["sh", str(d / "vrrd.sh")], env=env)
            try:
                end = time.monotonic() + 4
                while time.monotonic() < end:
                    if (d / "vrrd.log").exists() and '-> idle' in (d / "vrrd.log").read_text(): break
                    time.sleep(0.02)
                else: self.fail("daemon never entered idle")
                (d / "remove").touch()
                self.assertEqual(p.wait(timeout=5), 0)
                self.assertFalse((d / ".vrrd.pid").exists())
                self.assertFalse((d / ".vrrd.identity").exists())
            finally:
                if p.poll() is None: p.kill(); p.wait()

if __name__ == "__main__": unittest.main()

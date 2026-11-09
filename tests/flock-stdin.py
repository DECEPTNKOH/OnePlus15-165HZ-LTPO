#!/usr/bin/env python3
# Run: python3 tests/flock-stdin.py. Host simulation, not Android certification.
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / "module" / "lifecycle.sh"

class StdinLock(unittest.TestCase):
    def test_lock_survives_closing_fd9_in_external_command(self):
        real = shutil.which("flock")
        self.assertIsNotNone(real, "host flock is required")
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "bin").mkdir()
            (d / "lifecycle.sh").write_bytes(LIB.read_bytes())
            wrapper = d / "bin" / "flock"
            wrapper.write_text('#!/bin/sh\nexec 9>&-\nexec "$REAL_FLOCK" "$@"\n')
            wrapper.chmod(0o755)
            script = d / "check.sh"
            script.write_text('''
MODDIR=${0%/*}
PIDFILE="$MODDIR/.vrrd.pid"
say() { echo "$*" >&2; }
. "$MODDIR/lifecycle.sh"
vrr_acquire || exit 10
# The parent must retain its lock after the external command exits.
flock -n 0 <"$MODDIR/.vrrd.lock"
[ "$?" = 1 ] || exit 11
vrr_release
flock -n 0 <"$MODDIR/.vrrd.lock" || exit 12
[ ! -e "$PIDFILE" ] || exit 13
[ ! -e "$MODDIR/.vrrd.identity" ] || exit 14
''')
            env = dict(os.environ, REAL_FLOCK=real,
                       PATH=str(d / "bin") + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["sh", str(script)], env=env,
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

if __name__ == "__main__": unittest.main()

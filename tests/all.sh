#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bash tests/run.sh
python3 tests/lifecycle.py
python3 tests/settings-state.py
python3 tests/flock-stdin.py
python3 tests/restore-integration.py
python3 tests/patch-pipeline.py
python3 tests/xmlguard.py
python3 tests/package.py

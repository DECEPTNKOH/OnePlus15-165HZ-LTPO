## [v1.9.0-preview.3] - 2026-11-21

### Verified on device (CPH2747 / ColorOS 17)
- 165 Hz on interaction + 1 Hz idle at high brightness (`min_fps=1`).
- 165 Hz mode floors at 33 Hz; <=120 Hz modes reach 1 Hz (high brightness).
- Low brightness disables LTPO (anti-flicker) — panel behaviour, not the module.
- Setting map: 0=auto(165 ceiling), 1=120, 2=60, 3=165(in-range), 7=165(clamped).
- Auto alone does not boost to 165 on touch; the daemon is required.

### Changed
- Defaults ACTIVE_MODE=3 (in-range, robust) and IDLE_MODE=0 (leaves the 165 Hz
  mode on idle to reach 1 Hz; allows app-driven boost without touch).
- User config override `/data/adb/oneplus15-vrr-state/vrr.conf` survives updates.

### Fixed
- Baseline: write-ahead dirty marker; legit stock value snapshotted normally;
  leftover falls back to null; marker cleared on restore; recovery script on failure.
- WIN_OVERRIDE=all: `g` flag + coverage check (fails closed).
- DAEMON=0 pins ACTIVE_MODE once; startup lock retry; log rotation.
- power_status parsed as "kernel power :N" (on=0, off=2); screen-off idle poll 10s.
- Camera scan anchored + mktemp; diag PID via cmdline and config path from .mounted.
- customize: conflicting-module gate, Android 16 warning, persistent override conf.

### Tests
- Added dirty-marker, legit-value, win-override coverage, leftover-baseline cases.


## Install & verify
Flash via KernelSU/SukiSU, reboot. At max brightness: touch -> setting=3 / 165 Hz; idle 5s -> setting=0 / min_fps=1.

ZIP SHA-256: `28765f5fa424330bb26c392fcb4bd39f91f7db8c6beea5e0f5c8bdc796b09c1f`

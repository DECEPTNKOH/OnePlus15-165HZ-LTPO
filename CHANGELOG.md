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

## [v1.9.0-preview.2] - 2026-11-20

### Fixed
- **KernelSU (`ksud`) installation checksums:** Excluded `META-INF/*` from `SHA256SUMS` because `ksud` does not extract `META-INF` into `$MODPATH` during module installation, fixing `Archive checksum verification failed`.
- **Baseline snapshot & standalone sourcing (`settings-state.sh`):** Made dirty-baseline skipping opt-in (`VRR_SKIP_DIRTY_BASELINE=1` from `vrrd.sh`) and guarded `say` calls when sourced standalone, restoring full pass rate (`8/8`) in `tests/settings-state.py`.

### Verified
- Host checks (`sh tests/all.sh`) pass across syntax, `xmlguard`, `lifecycle`, `settings-state`, `patch-pipeline`, `restore-integration`, and `package` suites.
- Packaged and verified `OnePlus15-165HZ-LTPO-v1.9.0-preview.2.zip` (`SHA-256: 88d869e1c658b8accf4453e053dcfd2608570c93102be374df09f67826995b6f`) from commit `65cff2c` on `main`.

## v1.9.0-preview.1 — DECEPTNKOH fork — 2026-11-10

Experimental pre-release; iteration 1 complete, not a stable release.

- Replace trust in stale PID files with a lifecycle flock; support Android mksh
  by passing the lock through stdin. Never signal an unverified legacy PID.
- Add persistent per-user baseline storage and checked restoration, including
  deletion of an originally absent key, plus cooperative stop/uninstall.
- Require SAX + DOM validation before XML mounting; fail closed on parser,
  transformation, package-list or expected-insertion failures.
- Add 65 unittest cases across the registered Python suites, alongside the
  original sed/shell checks, a preview installer and allowlist packaging with
  DEX integrity checks and payload SHA-256 manifests. Disable automatic updates.
- Device validation on CPH2747 / CPH2747_17.0.0.102(EX01) / SukiSU: successful
  boot, real XML bind mount, selected 165 Hz active and 60 Hz idle modes under
  an idle policy capped at 120 Hz, restoration from setting 1 to 7 and restart.
- Physical 1 Hz is not independently verified. Reference-driver min_fps and
  test_te can expose software or substituted values. Long-term power use,
  every app scenario and real manager-driven uninstall remain unverified.

Tested ZIP runtime source: `87eb5e19122411066054316048b4dc03162b13bd`.
ZIP SHA-256: `2255ebdf4c237d3f28846bf036e71ffbe61ccbe528e03d2087cb503d7e51be42`.
Documentation commits after the runtime source do not rebuild the artifact.
See [release notes](docs/releases/v1.9.0-preview.1.md) for update precautions.
The earlier entries below are preserved upstream history, not new fork claims.

## v1.8

* The two camera fixes are no longer handed out together:
  * `<cameraOverride>` goes to every app holding the camera permission — it is
    free, the policy only consults it while the app actually holds a camera;
  * `enableWinOverride="false"` goes only to packages the daemon has actually
    seen streaming (`/data/adb/vrr_camera_used`) plus `CAMERA_PKGS`, because
    that flag also stops an app from requesting its own refresh rate.
  On a real config this shrinks the side effect from ~80 apps to the three that
  actually use a camera.
* `LEARN_CAMERA_USERS`: the daemon records the packages it sees streaming, so a
  newly used camera app is fully covered from the next boot.

## v1.7

* `KEEP_ACTIVE_CAMERA` now checks whether a camera is **actually streaming**
  (`dumpsys media.camera` → `Active Camera Clients`), instead of whether the
  foreground app merely holds the camera permission. About 80 apps hold that
  permission — browsers, maps, messengers, banking apps — so the previous check
  kept the panel at 165 Hz almost everywhere and the idle drop never happened.
  Now the high rate is held only while a viewfinder is live.

## v1.6.1

* Everything the user can see is in English now: module description, action
  button output, `diag.sh`, log lines and the comments in `vrr.conf`.
  Russian is kept in `README.ru.md` only.
* The action button report counted lines instead of tags for the 165 Hz entries.

## v1.6

* The camera app list moved to `/data/adb/vrr_camera_pkgs`, so it now survives
  a module reinstall.
* `KEEP_ACTIVE_CAMERA`: the daemon no longer drops to the idle state while a
  viewfinder is open — nobody swipes the screen in a camera app, and the idle
  state would cap the panel at 120 Hz.
* The camera scanner is invoked through `sh`: installing via `ksud` strips the
  execute bit, so it was silently never running.
* The action button report counted lines instead of tags.

## v1.5

* Built-in list of common camera apps, used on the very first boot — the device
  can only collect its own list after boot has completed.

## v1.4

* Both camera caps are lifted for every app holding `android.permission.CAMERA`;
  the list is collected on the device.
* Action button in the KernelSU manager: rebuilds the patch and prints a report.
* `WIN_OVERRIDE=camera` replaces the blanket ban, so the side effect (an app can
  no longer request its own refresh rate) is limited to camera apps.

## v1.3

* `enableWinOverride="false"` — skips the window-request revision that dragged
  viewfinders down to 60 Hz.

## v1.2

* `<cameraOverride>` and `highLightCameraRate="7"` — the "camera is open → 60 Hz"
  rule and the drop to 90 Hz at high brightness.

## v1.1

* `defaultMaxRate="165"` — app-switch animations are no longer clamped to 120 Hz.

## v1.0

* The patch is generated on the device; nothing is pinned to a firmware version.
* The daemon switches 165 ↔ 120 Hz on touch; the stock ADFR takes over when idle.

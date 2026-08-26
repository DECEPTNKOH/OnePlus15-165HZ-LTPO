# Changelog

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

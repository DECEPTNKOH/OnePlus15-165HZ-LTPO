# OnePlus 15 — 165 Hz with working LTPO

A Magisk/KernelSU module for the OnePlus 15 (`infinity`, CPH2747) on OxygenOS 16.
It runs the panel at **165 Hz while you interact** and lets it fall back to the stock
ADFR mode — down to **1 Hz** — when the screen is idle.

Русская версия: [README.ru.md](README.ru.md)

## Why not just pin 165 Hz

The panel physically cannot do both. Proven from the firmware, not guessed:

* In `dtbo.img` the panel timings `sdc_fhd_144` and `sdc_fhd_165` carry **zero**
  `qcom,mdss-dsi-adfr-min-fps-*` commands and no `oplus,adfr-min-fps-mapping-table`.
  The 120/90/60 timings do — with the ladder `[120, 60, 30, 20, 10, 1]`.
* The mode class shown by `dumpsys SurfaceFlinger` (`SA`/`SM`/`OA`) is the DT property
  `qcom,mdss-dsi-h-sync-skew` (`oplus_adfr_h_skew` in the kernel):
  0 = SDC_ADFR, 1 = SDC_MFR, 2 = OPLUS_ADFR.
* At 165 Hz `min_fps` reads 55 — that is `mvt_render` (165/3) from `oplus_vrr_config.json`.
  Writing 33, 15, 5 or 1 into it sticks but changes nothing: measured current stays
  136–148 mA, while the 120→60 Hz idle state draws **78 mA**. The panel keeps scanning
  at 165 regardless.

So the only way to get a low idle rate is to leave the 165 Hz mode when idle.
That is what this module does.

## How it works

1. **Patches `refresh_rate_config.xml`** so that the system refresh-rate setting becomes
   a switch: value `7` selects 165 Hz, value `1` selects the stock ADFR-capable 120 Hz mode.
   Every `rateId="a-b-c-d"` entry gets its 2nd slot set to `d` (144/165 lowered to 120)
   and its 4th slot set to `7`.
2. **Unlocks the boost paths** with `defaultMaxRate="165"`. Without that attribute its
   default is 120 (`PRIORITY_PAD_MIRAGE_TBL`), and `adjustRefreshForDefaultMax()` clamps
   app-switch animations, window overrides and floating windows down to 120.
3. **Frees the camera viewfinders.** Two independent caps are lifted for every app that
   holds `android.permission.CAMERA` — see [README.ru.md](README.ru.md) for the details.
4. **`vrrd.sh`** blocks on the touchscreen input device and flips the setting:
   touch → 165 Hz, `IDLE_TIMEOUT` seconds without touches → 120 Hz, after which the
   stock OTI/ADFR machinery takes the panel down to 1 Hz on its own.
   While idle the daemon does not wake at all — it sits in a blocking read, no polling.

## Not tied to a firmware version

The patch is generated on the device from whatever `refresh_rate_config.xml` is there.
No checksums, no version pins — after an OTA it simply rebuilds on the next boot.
Before mounting it verifies the file looks right, that the line count is unchanged and
that the patch actually produced 165 Hz entries. If anything fails, nothing is mounted
and the reason goes to `vrrd.log`.

The KernelSU **action button** rebuilds the patch on demand and prints a report.

## Measured

| state | mode | `min_fps` | current |
|---|---|---|---|
| interacting | 165 Hz (`crtc/fps` 165.4) | 55 | 136 mA |
| idle | 120 Hz, then 60 Hz | **1** | **78 mA** |

Note: OPlus gates the idle drop on brightness (`hw_nit_limit: 30`), so on a dim screen
`min_fps` stays high — that is stock behaviour, not this module.

## Credits and licence

Based on the idea and the original module by
[barsikus007 & 天伞桜](https://github.com/barsikus007/OnePlus15-165HZ) (MIT).
This rewrite is licensed under **GPL-3.0** — see [LICENSE](LICENSE).

# OnePlus 15 165Hz + LTPO — DECEPTNKOH Preview (`v1.9.0-preview.4`)

Experimental KernelSU / Magisk module fork for **OnePlus 15 (`CPH2747`, ColorOS 17)** that unlocks **165 Hz** refresh rate selection while preserving **LTPO idle downclocking**, guarded XML patching, safe daemon lifecycle control, and baseline setting restoration.

> **Status:** Experimental preview (`v1.9.0-preview.4`, commit `3b019e7` on `main`). Automatic module updates (`updateJson`) remain disabled in preview builds.

---

## Tested Preview Artifact

| Field | Value |
| :--- | :--- |
| **Module ID** | `OnePlus15-165HZ-LTPO` |
| **Version / Code** | `v1.9.0-preview.4` (`10904`) |
| **Source Commit** | `3b019e7` (`main`) |
| **Release ZIP** | `OnePlus15-165HZ-LTPO-v1.9.0-preview.4.zip` |
| **ZIP SHA-256** | `28765f5fa424330bb26c392fcb4bd39f91f7db8c6beea5e0f5c8bdc796b09c1f` |
| **Device & Root** | OnePlus 15 (`CPH2747`), ColorOS 17 (`CPH2747_17.0.0.102(EX01)`), KernelSU / SukiSU |

---

## Key Features & Architecture

- **Guarded XML Patching (`xmlguard` & `sed/`):** Validates patched `refresh_rate_config.xml` (`module/bin/xmlguard.jar` built from `tools/XmlGuard.java`) before bind-mounting over `/my_product/etc/refresh_rate_config.xml` in `post-fs-data.sh`. Supports `FORCE_ALL` (`1` = 165 Hz across apps, `0` = respect stock limits).
- **KernelSU (`ksud`) Checksum Compatibility:** Excludes `META-INF/*` from `SHA256SUMS` because `ksud` does not extract `META-INF` into `$MODPATH` during installation.
- **VRR Daemon & Lifecycle (`vrrd.sh`, `lifecycle.sh`, `service.sh`):** Switches `oplus_customize_screen_refresh_rate` between `ACTIVE_MODE` (`7` = 165 Hz) and `IDLE_MODE` (`1` = LTPO low-rate slot) using `IDLE_TIMEOUT` (`2`s default), `DEBOUNCE` (`0.5`s), `KEEP_ACTIVE_PKGS`, `WIN_OVERRIDE` (`camera` / `all` / `off`), and live camera checks (`KEEP_ACTIVE_CAMERA`, `CAMERA_165`, `LEARN_CAMERA_USERS`).
- **Baseline State Preservation (`settings-state.sh`):** Captures the user's prior refresh rate setting before first daemon write and restores it cleanly on stop or uninstall, without overwriting valid snapshots on restart.
- **Host Test Suite & Packaging (`tests/`, `tools/`, `.github/workflows/build.yml`):** Automated host verification (`sh tests/all.sh`) and reproducible archive packaging (`python3 tools/package.py --source-revision <sha>`).

---

## Repository Layout

```text
OnePlus15-165HZ-LTPO/
├── .github/workflows/build.yml   # CI workflow running host checks (tests/all.sh)
├── docs/                         # Iteration notes, baseline design, and release docs
├── module/                       # Flashable KernelSU / Magisk module payload
│   ├── bin/xmlguard.jar          # Compiled XML validator executed on-device
│   ├── sed/                      # force.sed / respect.sed XML transform rules
│   ├── post-fs-data.sh           # Early XML patch & bind-mount validation
│   ├── service.sh                # Late-start daemon launcher
│   ├── vrrd.sh                   # VRR active/idle state daemon
│   ├── lifecycle.sh              # Cooperative lock & stop/restart helpers
│   ├── settings-state.sh         # Baseline snapshot capture & restoration
│   ├── vrr.conf                  # User-tunable daemon & patch configuration
│   └── SHA256SUMS                # Payload integrity manifest (excludes META-INF)
├── tests/                        # Host unit & integration test suites (tests/all.sh)
├── tools/                        # XmlGuard.java, build-xmlguard.sh, package.py
├── CHANGELOG.md
├── README.md
└── README.ru.md
```

---

## Installation & Verification

1. Download `OnePlus15-165HZ-LTPO-v1.9.0-preview.4.zip` from [GitHub Releases](https://github.com/DECEPTNKOH/OnePlus15-165HZ-LTPO/releases/tag/v1.9.0-preview.4).
2. Flash in **KernelSU / SukiSU** (or via `ksud module install <path-to-zip>`) and **reboot**. Note that KernelSU removes `customize.sh` from `$MODPATH` after installation; all other payload files must match `SHA256SUMS`.
3. Verify mount, daemon process, and display mode:

```sh
mount | grep refresh_rate_config.xml
ps -ef | grep vrrd.sh
dumpsys display | grep -E "mBaseDisplayInfo|renderFrameRate|165"
```

> **Upgrades & Safety:** Flashing a preview ZIP overwrites `vrr.conf` with defaults — back up custom `KEEP_ACTIVE_PKGS`, `IDLE_TIMEOUT`, or `DAEMON` values first. Do not blindly restore legacy `v1.8` backups containing unsafe PID-based shutdown/uninstall logic.

---

## Verified vs. Unverified Behavior

- **Verified:** Validated XML bind mount, clean `ksud` install (`SHA256SUMS` verification), `165.0 Hz` mode selection on interaction, idle downclocking, baseline restoration (`1` -> `7`), and cooperative daemon stop/restart.
- **Unverified:** Independent hardware measurement of physical `1 Hz` panel refresh is not proven; `min_fps` and `test_te` can expose software states, filtered values, or fallbacks. Battery life, long-term stability, and all camera/game/video scenarios are still preview-grade.

---

## Upstream & Credits

Fork of `mrFrok/OnePlus15-165HZ-LTPO`. Original authors: `barsikus007`, `天伞桜`, `mrFrok`. Upstream history and `LICENSE` are preserved.
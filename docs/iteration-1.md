# Iteration 1 closeout - 2026-11-10

## Scope and state

Iteration complete; experimental preview retained, no stable-release claim.
Runtime source: 87eb5e19122411066054316048b4dc03162b13bd.
Installed version: v1.9.0-preview.1 / 10901.
ZIP SHA-256: 2255ebdf4c237d3f28846bf036e71ffbe61ccbe528e03d2087cb503d7e51be42.
Test device: OnePlus 15 CPH2747, CPH2747_17.0.0.102(EX01), SukiSU.
Kernel: 6.12.69-android16-6-g242e1a07f878-ab15865446-4k.

No open PRs or Issues were found in this fork during closeout. The working
branch is retained. No merge, branch deletion, tag or release is implied.

## Completed work

- Removed signals to unverified legacy PIDs during uninstall.
- Added lifecycle flock ownership, boot/start metadata and owner-only cleanup.
- Fixed Android mksh descriptor inheritance by passing the lock through stdin.
- Added validated persistent baseline storage, explicit Android user targeting,
  absent-key deletion and restoration readback.
- Integrated cooperative stop/uninstall and restore-before-lock-release.
- Added mandatory SAX + DOM checks before XML bind mounting. Android DOM alone
  accepted duplicate attributes; the SAX preflight rejected the negative test.
- Added checked transformations, package validation/escaping and insertion checks.
- Added preview-only metadata, no updateJson, host CI and allowlist packaging.
- Added archive/DEX integrity checks, payload manifest and installer checksums.

## Verification record

The locally built package completed tests/all.sh before PREVIEW_ZIP_READY.
The seven Python suites contain 65 unittest cases, in addition to original
sed-rule and shell-syntax checks. They are not a claim of passing GitHub CI.

Android parser probe accepted the current 2165-item config and rejected a
duplicate-attribute document. A private-copy pipeline probe returned 0 in
1.93 seconds with real parsing and simulated mount calls; system XML was
unchanged. That timing was measured after Android boot, not during early boot.

Actual preview boot subsequently completed. The validated XML was bind mounted
from the installed module and the daemon command line was verified. SurfaceFlinger
reported selected modes 165 Hz after interaction and 60 Hz in idle, with idle
policy capped at 120 Hz. Cooperative stop restored setting 1 to baseline 7 for
user 0, released the lock, and allowed a new verified daemon process to start.

## Interpretation limits

Reference driver blob: ea909af3711c84f0234e93c1ae519e52ac28080b from
OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8850. It is not a
proven match for the installed binary. Live msm_drm srcversion recorded:
9C2996288B522E717B7A9FB.

In the reference, min_fps reads sa_min_fps in relevant modes. The TE timer can
copy that value; the IRQ path filters or replaces measured intervals and can
copy the minimum in idle. BIT14 is software marker; live config 0x6e41 has
that bit set if the same definition applies. Registration and handlers can
return early for software marker. Physical 1 Hz is therefore not independently
verified. Lost kernel-message context prevents identifying earlier IRQ stack
messages conclusively. No manual TE IRQ enabling or adfr_config changes were
performed by our diagnostic scripts. No kernel was flashed.

Long-term power use, every app scenario and real manager-driven uninstall
remain unverified. They are outside the closed iteration, not silently passed.

## Retention and cleanup policy

Keep the live module, .vrrd.lock, PID/identity metadata, .mounted, persistent
baseline and camera lists. Keep one verified installer, source snapshot,
selected reports and the original v1.8 backup. Preserve LICENSE and history.

Phone cleanup requires a read-only inventory and archive verification before
deleting exact temporary paths. Do not delete any probe path still involved
in a mount. Do not touch unrelated Android projects. Turn off only this
module debug logging, if requested, through cooperative stop/restart; do not
change active/idle modes, timeout, kernel flags or the saved baseline.

This report does not claim that phone cleanup has already been performed.

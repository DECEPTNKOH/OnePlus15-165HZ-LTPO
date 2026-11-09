# OnePlus 15 refresh switching - DECEPTNKOH preview

Development iteration 1 is complete. The working result remains experimental
v1.9.0-preview.1, not a stable release. No further kernel or TE experiments are
part of this iteration. Work is retained on `fix/daemon-lifecycle`; this
closeout does not merge or delete branches.

## Frozen tested artifact

- Runtime source commit: `87eb5e19122411066054316048b4dc03162b13bd`.
- Module ID: `OnePlus15-165HZ-LTPO`; versionCode: `10901`.
- ZIP: `OnePlus15-165HZ-LTPO-v1.9.0-preview.1.zip`.
- ZIP SHA-256: `2255ebdf4c237d3f28846bf036e71ffbe61ccbe528e03d2087cb503d7e51be42`.
- Device tested: CPH2747, build `CPH2747_17.0.0.102(EX01)`, SukiSU.

Later documentation-only commits do not replace or rebuild this artifact.
The binary ZIP is built locally; this repository has not published a stable
release or enabled automatic module updates. CI status is not attested by
this report.

## Verified and unverified behavior

Verified on the test device: validated XML bind mount, correct daemon process,
165 Hz selected display mode after interaction, 60 Hz selected mode in idle
under a policy capped at 120 Hz, baseline restoration from setting 1 to 7,
and cooperative stop/restart. Packaging completed the host test suites.

Physical 1 Hz panel refresh is NOT independently verified. `min_fps` is a
software parameter in the reference driver, and `test_te` can expose software
markers, filtered results, timing fallbacks or copied minimum values. Neither
node alone is proof of physical panel frequency. The published reference driver
is not proven identical to the installed ColorOS 17 binary.

## Keep and avoid

Keep the installed module, its lifecycle lock and metadata, the persistent
setting baseline, camera package lists, one verified ZIP, source snapshot and
the original v1.8 backup. Do not blindly restore or run the old backup: its
legacy PID-based shutdown/uninstall logic was unsafe.

Do not use Action or killall for hot rebuilding/restarting this preview. Do not
write to test_te or adfr_config, clear software-marker bits, or flash a different
kernel as part of cleanup. Debug logging may be disabled as a separate local
configuration change using the tested cooperative stop/restart procedure.

See [Russian overview](README.ru.md), [iteration report](docs/iteration-1.md),
[build instructions](docs/preview-build.md) and
[baseline semantics](docs/settings-baseline.md). KernelSU removes customize.sh
after installation; post-install checksum verification must account only for
that consumed installer file, not ignore arbitrary missing runtime files.

## Upstream

Fork of mrFrok/OnePlus15-165HZ-LTPO, with original work credited to
barsikus007, 天伞桜 and mrFrok. Upstream history and LICENSE are retained.

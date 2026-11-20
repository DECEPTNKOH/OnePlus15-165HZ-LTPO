# DECEPTNKOH preview build

This is experimental v1.9.0-preview.1, not a stable release. The module ID is
unchanged so the root manager updates v1.8 instead of installing two competing
modules. Automatic update metadata is deliberately absent. CI runs host tests
only: it neither publishes a release nor produces a ready-to-install artifact.

On the build machine/Termux, obtain a clean checkout of the full source commit,
then run:

```sh
sh tools/build-xmlguard.sh
python3 tools/package.py --source-revision FULL_40_CHARACTER_COMMIT_SHA
```

Packaging runs all host tests and requires JDK, Python 3, Bash and the test
utilities. Building the validator also requires d8. Generated JAR files are not
stored in Git. The archive includes a file allowlist, license, source revision
and payload SHA-256 manifest. The installer verifies extracted runtime files
against SHA256SUMS; META-INF is excluded because managers may omit it. DEX header/checksum checks are integrity checks,
not proof that arbitrary bytecode matches the Java source. Use the checked-in
builder and keep the Android positive/negative parser probe result.

Source revision is supplied by the builder and recorded, not remotely attested.
Use the exact clean checkout; do not label modified files with an older SHA.
The packager refuses to overwrite an existing ZIP. Archive timestamps outside
the JAR are fixed; JAR rebuilds may have different hashes due to ZIP metadata.

Installation is restricted to Android 17 on CPH2747 through the Android root
manager. Installer checks do not prove boot compatibility with SukiSU. No hot
install is requested. The default vrr.conf replaces previous custom settings;
keep the existing backup and compare before changing anything.

Read docs/settings-baseline.md before upgrading from v1.8. A reboot is required.
Keep recovery access and the old module backup available. Do not blindly remove
v1.8 using its old PID-based uninstall script. Device boot validation of this
preview is pending; do not advertise it as verified for daily use.

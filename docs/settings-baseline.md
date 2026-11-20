# Refresh setting baseline and migration

The daemon saves the current Settings.Secure value and Android user ID before
its first settings write. The snapshot lives outside the module directory at
`/data/adb/oneplus15-vrr-state/baseline` and is not overwritten on restart.
An absent key is restored with `settings delete`, not the literal text `null`.

For upgrades from v1.8 this is an observed upgrade baseline, NOT a recovered
pre-install setting. If v1.8 already changed the value, its earlier value is
unknown. Do not describe this migration snapshot as the original setting.

Graceful daemon exit restores the baseline under its lifecycle lock. Uninstall
requests stop, waits up to approximately 15 seconds for that lock, and restores
and verifies the saved value. Only successful uninstall restoration retires
the snapshot. No snapshot means no guessed fallback and no settings write.
Restoration failure leaves the snapshot for recovery and returns an error.

SIGKILL, power loss, or disabling the module before a subsequent boot cannot
run an exit handler. A preserved snapshot is not a guarantee of immediate
restoration in those cases. Android runtime user switching is not managed;
the daemon targets the saved user ID.

Do not hot-replace an existing running v1.8 daemon. Upgrade testing requires a
reboot; old code does not participate in the new lifecycle lock.

Host checks (mocked Android settings):

```sh
python3 tests/lifecycle.py
python3 tests/settings-state.py
python3 tests/flock-stdin.py
sh tests/uninstall-safety.sh
```

These are not device-level validation or proof of the panel refresh rate.

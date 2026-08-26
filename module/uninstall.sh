#!/system/bin/sh
# Restore the refresh rate setting when the module is removed.
# Without this the system could be left at value 1, which without our patched
# config means the stock 90 Hz mode, because the daemon set it before removal.

MODDIR=${0%/*}
PID=$(cat "$MODDIR/.vrrd.pid" 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null

cmd settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null || \
  settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null

exit 0

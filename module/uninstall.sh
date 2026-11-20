#!/system/bin/sh
# Request cooperative shutdown. Never signal a PID from a file.
MODDIR=${0%/*}
PIDFILE="$MODDIR/.vrrd.pid"
say() { echo "uninstall: $*" >> "$MODDIR/vrrd.log"; }
[ -r "$MODDIR/lifecycle.sh" ] && [ -r "$MODDIR/settings-state.sh" ] || exit 1
. "$MODDIR/lifecycle.sh"
. "$MODDIR/settings-state.sh"
: > "$MODDIR/stop" || exit 1
i=0
while :; do
  vrr_acquire
  rc=$?
  [ "$rc" = 0 ] && break
  if [ "$rc" != 1 ] || [ "$i" -ge 15 ]; then
    say "ERROR: cannot acquire lifecycle lock; baseline retained"
    exit 1
  fi
  sleep 1
  i=$((i + 1))
done
if [ ! -e "$VRR_BASELINE" ] && [ ! -L "$VRR_BASELINE" ]; then
  say "no saved baseline; leaving setting unchanged"
  exit 0
fi
if vrr_baseline_restore; then
  rm -f "$VRR_BASELINE" || exit 1
  say "baseline restored and snapshot retired"
else
  say "ERROR: restore failed; baseline retained at $VRR_BASELINE"
  exit 1
fi

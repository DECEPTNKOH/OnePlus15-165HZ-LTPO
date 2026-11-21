#!/system/bin/sh
# OnePlus15-165HZ-LTPO — starts the daemon once the device has booted.

MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"

say() { echo "[$(date '+%m-%d %H:%M:%S')] service: $*" >> "$LOG"; }

DAEMON=1
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"
OVRR_CONF=/data/adb/oneplus15-vrr-state/vrr.conf
if [ -f "$OVRR_CONF" ]; then
  if sh -n "$OVRR_CONF" 2>/dev/null; then
    . "$OVRR_CONF"
  else
    echo "override config $OVRR_CONF has a syntax error; ignored" >> "$LOG"
  fi
fi

# wait for boot to complete
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 5

if [ ! -f "$MODDIR/.mounted" ]; then
  say "config was not mounted (see above) — not starting the daemon"
  exit 0
fi

# does the panel expose a 165 Hz mode at all
if dumpsys SurfaceFlinger 2>/dev/null | grep -qE '16[0-9]\.[0-9]+' ; then
  say "165 Hz mode found in SurfaceFlinger"
else
  say "warning: no 165 Hz display mode found, rateId=7 will do nothing"
fi

if [ "$DAEMON" != "1" ]; then
  say "DAEMON=0 — switching disabled; pinning ACTIVE_MODE once"
  ACTIVE_MODE=${ACTIVE_MODE:-7}
  PIDFILE="$MODDIR/.vrrd.pid"
  if [ -r "$MODDIR/lifecycle.sh" ] && [ -r "$MODDIR/settings-state.sh" ]; then
    . "$MODDIR/lifecycle.sh"
    if vrr_acquire; then
      . "$MODDIR/settings-state.sh"
      if VRR_SKIP_DIRTY_BASELINE=1 vrr_baseline_prepare && vrr_mode_write "$ACTIVE_MODE"; then
        say "pinned $VRR_KEY=$ACTIVE_MODE (restored on uninstall)"
      else
        say "ERROR: could not pin ACTIVE_MODE"
      fi
      vrr_release
    else
      say "ERROR: lock busy; cannot pin ACTIVE_MODE"
    fi
  else
    say "ERROR: lifecycle/settings-state helpers missing"
  fi
  exit 0
fi

# refresh the camera app list — it is applied the next time the patch is built
if [ "$CAMERA_165" = "1" ]; then
  WAS=0
  [ -s "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ] && WAS=1
  say "$(sh "$MODDIR/scan_camera_pkgs.sh" 2>&1 | tail -1)"
  if [ "$WAS" = "0" ] && [ -s "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ]; then
    say "camera app list collected for the first time — it applies on the next boot (or via the action button)"
  fi
fi

chmod 0755 "$MODDIR/vrrd.sh"
nohup "$MODDIR/vrrd.sh" >/dev/null 2>&1 &
say "daemon started"
exit 0

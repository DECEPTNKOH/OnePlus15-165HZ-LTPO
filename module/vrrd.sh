#!/system/bin/sh
# OnePlus15-165HZ-LTPO refresh daemon.
# Idle waits are bounded to observe stop/remove flags, not zero-wakeup.
MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"
PIDFILE="$MODDIR/.vrrd.pid"
KEY=oplus_customize_screen_refresh_rate
ACTIVE_MODE=7
IDLE_MODE=1
IDLE_TIMEOUT=2
DEBOUNCE=0.5
DEBUG=0
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"
log() { [ "$DEBUG" = "1" ] && echo "[$(date '+%m-%d %H:%M:%S')] vrrd: $*" >> "$LOG"; return 0; }
say() { echo "[$(date '+%m-%d %H:%M:%S')] vrrd: $*" >> "$LOG"; }
[ -r "$MODDIR/lifecycle.sh" ] || { say "ERROR: lifecycle.sh missing"; exit 1; }
. "$MODDIR/lifecycle.sh"
vrr_acquire
rc=$?
[ "$rc" = 0 ] || exit "$rc"
[ -r "$MODDIR/settings-state.sh" ] || { say "ERROR: settings-state.sh missing"; exit 1; }
. "$MODDIR/settings-state.sh"
VRR_DIRTY=0
put_mode() {
  # Even a failed command might have partially applied its write.
  VRR_DIRTY=1
  vrr_mode_write "$1"
}
KEEP_RECHECK=30
CAM_RECHECK=10
KEEP_UNTIL=0
CAM_UNTIL=0
camera_in_use() {
  [ "$KEEP_ACTIVE_CAMERA" = "1" ] || return 1
  now=$(date +%s)
  [ "$now" -lt "$CAM_UNTIL" ] && return 0
  clients=$(dumpsys media.camera 2>/dev/null | grep -A6 "Active Camera Clients:" |
    grep -oE "Client Package Name: [A-Za-z0-9_.]+" | sed "s/.*: //")
  [ -z "$clients" ] && return 1
  CAM_UNTIL=$((now + CAM_RECHECK))
  log "staying active: camera in use by $clients"
  if [ "$LEARN_CAMERA_USERS" = "1" ]; then
    used="${CAMERA_USED:-/data/adb/vrr_camera_used}"
    for c in $clients; do
      grep -Fxq "$c" "$used" 2>/dev/null || { echo "$c" >> "$used"; say "learned camera user: $c"; }
    done
  fi
  return 0
}
keep_active_pkg() {
  KEEP="$KEEP_ACTIVE_PKGS"
  [ -z "$KEEP" ] && return 1
  now=$(date +%s)
  [ "$now" -lt "$KEEP_UNTIL" ] && return 0
  cur=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=" | tr ' ' '\n' | grep -m1 '/' | cut -d/ -f1)
  [ -z "$cur" ] && return 1
  for p in $KEEP; do
    if [ "$p" = "$cur" ]; then
      KEEP_UNTIL=$((now + KEEP_RECHECK))
      log "staying active: $cur is in the foreground"
      return 0
    fi
  done
  return 1
}
state=""
set_state() {
  [ "$1" = "$state" ] && return 0
  if [ "$1" = idle ] && { camera_in_use || keep_active_pkg; }; then return 0; fi
  case "$1" in
    active) mode="$ACTIVE_MODE" ;;
    idle) mode="$IDLE_MODE" ;;
    *) return 1 ;;
  esac
  if put_mode "$mode"; then
    state="$1"
    log "-> $state ($mode)"
  else
    say "ERROR: setting write failed for $1 ($mode)"
    return 1
  fi
}
CHILD=""
finish() {
  result=$?
  trap - 0
  trap '' TERM INT HUP
  if [ -n "$CHILD" ]; then
    kill "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
    CHILD=""
  fi
  if [ "$VRR_DIRTY" = 1 ]; then
    if vrr_baseline_restore; then
      say "baseline restored for user $VRR_USER"
    else
      say "ERROR: baseline restore failed; snapshot retained at $VRR_BASELINE"
      result=1
    fi
  fi
  vrr_release
  exit "$result"
}
cleanup() { exit 0; }
trap finish 0
trap cleanup TERM INT HUP
wait_event() {
  # Do not let input helpers retain the lock after a daemon crash.
  timeout "$1" getevent -c 1 "$DEV" 9>&- >/dev/null 2>&1 &
  CHILD=$!
  wait "$CHILD"
  rc=$?
  CHILD=""
  return "$rc"
}
find_touch() {
  for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    if getevent -pl "$d" 2>/dev/null | grep -q ABS_MT_POSITION_X; then echo "$d"; return 0; fi
  done
  return 1
}
# Do not start switching when a stop/removal was already requested.
if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/stop" ] || [ -f "$MODDIR/remove" ]; then exit 0; fi
DEV=$(find_touch)
if [ -z "$DEV" ]; then say "touchscreen not found, daemon not started"; exit 1; fi
vrr_baseline_prepare || { say "ERROR: baseline unavailable; refusing setting writes"; exit 1; }
say "baseline user=$VRR_USER value=$VRR_VALUE; observed before first write, not necessarily before original install"
say "input device: $DEV, idle after ${IDLE_TIMEOUT}s, ACTIVE=$ACTIVE_MODE IDLE=$IDLE_MODE"
set_state active
while :; do
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/stop" ] || [ -f "$MODDIR/remove" ]; then
    say "stop/remove flag found"
    cleanup
  fi
  if [ ! -e "$DEV" ]; then
    say "$DEV disappeared, looking for it again"
    sleep 2
    NEW=$(find_touch)
    if [ -n "$NEW" ]; then DEV="$NEW"; else continue; fi
  fi
  if [ "$state" = idle ]; then
    if wait_event 2; then
      set_state active
      sleep "$DEBOUNCE"
    else
      rc=$?
      [ "$rc" = 124 ] || { say "input wait failed: $rc"; sleep 2; }
    fi
  else
    if wait_event "$IDLE_TIMEOUT"; then
      set_state active
      sleep "$DEBOUNCE"
    else
      rc=$?
      if [ "$rc" = 124 ]; then set_state idle; else say "input wait failed: $rc"; sleep 2; fi
    fi
  fi
done

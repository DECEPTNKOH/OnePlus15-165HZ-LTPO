#!/system/bin/sh
# OnePlus15-165HZ-LTPO — refresh rate switching daemon.
#
# While the user touches the screen the setting is ACTIVE_MODE (165 Hz once the
# config is patched). After IDLE_TIMEOUT seconds without a touch it becomes
# IDLE_MODE — the stock ADFR-capable 120 Hz mode, which can drop to 1 Hz.
#
# Input events are awaited with a blocking getevent, so while idle the daemon
# never wakes up: no timers, no polling.

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

# --- single instance -----------------------------------------------------
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && [ -d "/proc/$OLD" ]; then
    say "already running (pid $OLD), exiting"
    exit 0
  fi
fi
echo $$ > "$PIDFILE"

put_mode() {
  if ! cmd settings put secure "$KEY" "$1" 2>/dev/null; then
    settings put secure "$KEY" "$1" 2>/dev/null
  fi
}

get_mode() {
  cmd settings get secure "$KEY" 2>/dev/null || settings get secure "$KEY" 2>/dev/null
}

# Does the foreground app ask to stay at the high rate?
# The answer is cached for KEEP_RECHECK seconds so dumpsys is not called in a loop.
KEEP_RECHECK=30
KEEP_UNTIL=0
keep_active_pkg() {
  KEEP="$KEEP_ACTIVE_PKGS"
  # nobody swipes in a viewfinder, and the idle state would cap the panel at 120
  if [ "$KEEP_ACTIVE_CAMERA" = "1" ] && [ -f "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ]; then
    KEEP="$KEEP $(cat "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}")"
  fi
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
  if [ "$1" = "idle" ] && keep_active_pkg; then
    return 0
  fi
  state="$1"
  case "$1" in
    active) put_mode "$ACTIVE_MODE"; log "-> active ($ACTIVE_MODE)" ;;
    idle)   put_mode "$IDLE_MODE";   log "-> idle ($IDLE_MODE)" ;;
  esac
}

CHILD=""
cleanup() {
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  say "stopping, restoring $ACTIVE_MODE"
  put_mode "$ACTIVE_MODE"
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup TERM INT HUP

# Wait for an input event. $1 is a timeout in seconds, empty means wait forever.
# Run it in the background and wait, otherwise a signal (kill) would not be
# handled while getevent sits in a blocking read.
wait_event() {
  if [ -n "$1" ]; then
    timeout "$1" getevent -c 1 "$DEV" >/dev/null 2>&1 &
  else
    getevent -c 1 "$DEV" >/dev/null 2>&1 &
  fi
  CHILD=$!
  wait "$CHILD"
  rc=$?
  CHILD=""
  return $rc
}

# --- find the touchscreen ------------------------------------------------
find_touch() {
  for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    if getevent -pl "$d" 2>/dev/null | grep -q "ABS_MT_POSITION_X"; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

DEV=$(find_touch)
if [ -z "$DEV" ]; then
  say "touchscreen not found, daemon not started"
  rm -f "$PIDFILE"
  exit 1
fi
say "input device: $DEV, idle after ${IDLE_TIMEOUT}s, ACTIVE=$ACTIVE_MODE IDLE=$IDLE_MODE"

set_state active

# --- main loop -----------------------------------------------------------
while :; do
  # runtime kill switch: the Magisk/KSU flag or our own
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/stop" ]; then
    say "stop flag found"
    cleanup
  fi

  if [ ! -e "$DEV" ]; then
    say "$DEV disappeared, looking for it again"
    sleep 2
    NEW=$(find_touch)
    if [ -n "$NEW" ]; then DEV="$NEW"; say "new device: $DEV"; else continue; fi
  fi

  if [ "$state" = "idle" ]; then
    # block until the first touch — zero wakeups while idle
    if wait_event ""; then
      set_state active
      sleep "$DEBOUNCE"
    else
      sleep 2
    fi
  else
    if wait_event "$IDLE_TIMEOUT"; then
      sleep "$DEBOUNCE"
    else
      set_state idle
    fi
  fi
done

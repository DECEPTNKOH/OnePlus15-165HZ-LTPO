#!/system/bin/sh
# OnePlus15-165HZ-LTPO — демон переключения частоты.
#
# Пока пользователь касается экрана — режим ACTIVE_MODE (после патча конфига
# это 165 Гц). Через IDLE_TIMEOUT секунд без касаний — IDLE_MODE (стоковый
# ADFR-режим панели на 120 Гц, который умеет опускаться до 1 Гц).
#
# Ждём события блокирующим getevent, поэтому в простое демон не просыпается
# вообще: ни таймеров, ни поллинга.

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

# --- одна копия ----------------------------------------------------------
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && [ -d "/proc/$OLD" ]; then
    say "уже запущен (pid $OLD), выходим"
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

# Приложение на экране просило остаться на высокой частоте?
# Результат кэшируется на KEEP_RECHECK секунд, чтобы не звать dumpsys в цикле.
KEEP_RECHECK=30
KEEP_UNTIL=0
keep_active_pkg() {
  KEEP="$KEEP_ACTIVE_PKGS"
  # в видоискателе по экрану не возят, а простой уронил бы потолок до 120
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
      log "остаёмся активными: на экране $cur"
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
  say "останов, возвращаем $ACTIVE_MODE"
  put_mode "$ACTIVE_MODE"
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup TERM INT HUP

# Ждём событие ввода. $1 — таймаут в секундах, пусто — ждать бесконечно.
# Запускаем фоном и ждём через wait, иначе сигнал (kill) не обработается,
# пока getevent висит в блокирующем чтении.
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

# --- ищем тачскрин -------------------------------------------------------
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
  say "тачскрин не найден, демон не запущен"
  rm -f "$PIDFILE"
  exit 1
fi
say "устройство ввода: $DEV, простой через ${IDLE_TIMEOUT}с, ACTIVE=$ACTIVE_MODE IDLE=$IDLE_MODE"

set_state active

# --- основной цикл -------------------------------------------------------
while :; do
  # выключение на лету: флаг Magisk/KSU или собственный
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/stop" ]; then
    say "найден флаг остановки"
    cleanup
  fi

  if [ ! -e "$DEV" ]; then
    say "устройство $DEV пропало, ищем заново"
    sleep 2
    NEW=$(find_touch)
    if [ -n "$NEW" ]; then DEV="$NEW"; say "новое устройство: $DEV"; else continue; fi
  fi

  if [ "$state" = "idle" ]; then
    # блокируемся до первого касания — ни одного пробуждения в простое
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

#!/system/bin/sh
# OnePlus15-165HZ-LTPO — запуск демона после загрузки.

MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"

say() { echo "[$(date '+%m-%d %H:%M:%S')] service: $*" >> "$LOG"; }

DAEMON=1
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"

# ждём полной загрузки
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 5

if [ ! -f "$MODDIR/.mounted" ]; then
  say "конфиг не подменён (см. выше) — демон не запускаем"
  exit 0
fi

# есть ли вообще режим 165 Гц у панели
if dumpsys SurfaceFlinger 2>/dev/null | grep -qE '16[0-9]\.[0-9]+' ; then
  say "режим 165 Гц найден в SurfaceFlinger"
else
  say "внимание: режим 165 Гц у дисплея не найден, rateId=7 работать не будет"
fi

if [ "$DAEMON" != "1" ]; then
  say "DAEMON=0 — переключение выключено, остаётся постоянный высокий режим"
  exit 0
fi

# обновляем список камерных приложений — применится при следующей сборке патча
if [ "$CAMERA_165" = "1" ]; then
  WAS=0
  [ -s "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ] && WAS=1
  say "$(sh "$MODDIR/scan_camera_pkgs.sh" 2>&1 | tail -1)"
  if [ "$WAS" = "0" ] && [ -s "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ]; then
    say "список камерных приложений собран впервые — он применится при следующей загрузке (или по кнопке «Действие»)"
  fi
fi

chmod 0755 "$MODDIR/vrrd.sh"
nohup "$MODDIR/vrrd.sh" >/dev/null 2>&1 &
say "демон запущен"
exit 0

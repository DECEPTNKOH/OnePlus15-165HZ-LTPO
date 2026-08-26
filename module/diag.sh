#!/system/bin/sh
# Диагностика: su -c /data/adb/modules/OnePlus15-165HZ-LTPO/diag.sh
MODDIR=${0%/*}

echo "=== модуль ==="
[ -f "$MODDIR/.mounted" ] && echo "подменён: $(cat "$MODDIR/.mounted")" || echo "конфиг НЕ подменён"
PID=$(cat "$MODDIR/.vrrd.pid" 2>/dev/null)
if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then echo "демон: работает (pid $PID)"; else echo "демон: не работает"; fi
echo "настройка: $(cmd settings get secure oplus_customize_screen_refresh_rate 2>/dev/null)"
echo "peak_refresh_rate: $(cmd settings get system peak_refresh_rate 2>/dev/null)"

echo
echo "=== действующий конфиг ==="
grep -m1 -oE '<refresh_rate_config[^>]*>' /my_product/etc/refresh_rate_config.xml 2>/dev/null
grep -m1 -oE '<config [^>]*>' /my_product/etc/refresh_rate_config.xml 2>/dev/null

echo
echo "=== SurfaceFlinger ==="
dumpsys SurfaceFlinger 2>/dev/null | grep -A8 "OPlusRefreshRateSelector"
dumpsys SurfaceFlinger 2>/dev/null | grep -iE "ADFR Mode|Auto Mode|MinFps|IdleFps|activeMode|renderRate|Current Policy|refresh rate"

echo
echo "=== панель ==="
for n in min_fps adfr_config dynamic_float_te high_precision_rscc_set power_status; do
  [ -r "/sys/kernel/oplus_display/$n" ] && echo "$n = $(cat /sys/kernel/oplus_display/$n 2>/dev/null)"
done

echo
echo "=== накопленная статистика по частотам ==="
dumpsys SurfaceFlinger 2>/dev/null | grep -E "^[0-9]+\.[0-9]+ Hz:|ScreenOff:"

echo
echo "=== лог модуля (хвост) ==="
tail -n 25 "$MODDIR/vrrd.log" 2>/dev/null

#!/system/bin/sh
# Diagnostics: su -c /data/adb/modules/OnePlus15-165HZ-LTPO/diag.sh
MODDIR=${0%/*}

echo "=== module ==="
[ -f "$MODDIR/.mounted" ] && echo "mounted over: $(cat "$MODDIR/.mounted")" || echo "config is NOT mounted"
PID=$(cat "$MODDIR/.vrrd.pid" 2>/dev/null)
if [ -n "$PID" ] && [ -d "/proc/$PID" ] && grep -qa 'vrrd\.sh' "/proc/$PID/cmdline" 2>/dev/null; then
  echo "daemon: running (pid $PID)"
else
  echo "daemon: not running"
fi
echo "setting: $(cmd settings get secure oplus_customize_screen_refresh_rate 2>/dev/null)"
echo "peak_refresh_rate: $(cmd settings get system peak_refresh_rate 2>/dev/null)"

echo
echo "=== active config ==="
CFG=$(cat "$MODDIR/.mounted" 2>/dev/null)
[ -n "$CFG" ] || CFG=/my_product/etc/refresh_rate_config.xml
grep -m1 -oE '<refresh_rate_config[^>]*>' "$CFG" 2>/dev/null
grep -m1 -oE '<config [^>]*>' "$CFG" 2>/dev/null

echo
echo "=== SurfaceFlinger ==="
dumpsys SurfaceFlinger 2>/dev/null | grep -A8 "OPlusRefreshRateSelector"
dumpsys SurfaceFlinger 2>/dev/null | grep -iE "ADFR Mode|Auto Mode|MinFps|IdleFps|activeMode|renderRate|Current Policy|refresh rate"

echo
echo "=== panel ==="
for n in min_fps adfr_config dynamic_float_te high_precision_rscc_set power_status; do
  [ -r "/sys/kernel/oplus_display/$n" ] && echo "$n = $(cat /sys/kernel/oplus_display/$n 2>/dev/null)"
done

echo
echo "=== accumulated time per refresh rate ==="
dumpsys SurfaceFlinger 2>/dev/null | grep -E "^[0-9]+\.[0-9]+ Hz:|ScreenOff:"

echo
echo "=== module log (tail) ==="
tail -n 25 "$MODDIR/vrrd.log" 2>/dev/null

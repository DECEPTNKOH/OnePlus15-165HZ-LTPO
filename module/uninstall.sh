#!/system/bin/sh
# Вернуть настройку частоты в нормальное значение при удалении модуля.
# Без этого система могла бы остаться в режиме 1 (после удаления модуля
# это стоковые 90 Гц), потому что демон переключил её перед удалением.

MODDIR=${0%/*}
PID=$(cat "$MODDIR/.vrrd.pid" 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null

cmd settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null || \
  settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null

exit 0

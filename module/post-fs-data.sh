#!/system/bin/sh
# OnePlus15-165HZ-LTPO — генерация и подмена refresh_rate_config.xml.
#
# Патч делается на устройстве из живого файла, поэтому модуль не привязан
# к конкретной версии прошивки. Если файл не найден, не похож на
# refresh_rate_config или патч не дал изменений — ничего не монтируется.

MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"
STATE="$MODDIR/.mounted"

log() { echo "[$(date '+%m-%d %H:%M:%S')] post-fs-data: $*" >> "$LOG"; }

rm -f "$STATE"
: > "$LOG"

FORCE_ALL=1
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"

# --- ищем исходный конфиг ------------------------------------------------
SRC=""
for p in /my_product/etc /my_stock/etc /product/etc /system/etc /vendor/etc; do
  if [ -f "$p/refresh_rate_config.xml" ]; then SRC="$p/refresh_rate_config.xml"; break; fi
done
if [ -z "$SRC" ]; then
  log "refresh_rate_config.xml не найден — выходим"
  exit 0
fi
log "исходник: $SRC"

# --- проверяем, что это действительно тот формат -------------------------
if ! grep -q "<refresh_rate_config" "$SRC"; then
  log "ОТМЕНА: в $SRC нет тега <refresh_rate_config"
  exit 0
fi
SRC_ITEMS=$(grep -cE 'rateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$SRC")
if [ "${SRC_ITEMS:-0}" -lt 10 ]; then
  log "ОТМЕНА: формат rateId не распознан (найдено $SRC_ITEMS записей)"
  exit 0
fi

# уже наш файл? (значит скрипт запустили повторно поверх живого mount)
if grep -q 'version="20991231"' "$SRC"; then
  log "ОТМЕНА: по пути $SRC уже лежит наш пропатченный файл, повторно не патчим"
  echo "$SRC" > "$STATE"
  exit 0
fi

# --- генерируем ----------------------------------------------------------
PATCH_DIR="$MODDIR/patched"
DST="$PATCH_DIR/refresh_rate_config.xml"
mkdir -p "$PATCH_DIR"
rm -f "$DST"

if [ "$FORCE_ALL" = "1" ]; then
  RULES="$MODDIR/sed/force.sed"
else
  RULES="$MODDIR/sed/respect.sed"
fi
log "правила: $RULES (FORCE_ALL=$FORCE_ALL)"

if ! sed -E -f "$RULES" "$SRC" > "$DST" 2>>"$LOG"; then
  log "ОТМЕНА: sed завершился с ошибкой"
  rm -f "$DST"
  exit 0
fi

# --- запретить ронять частоту запросом окна -------------------------------
# WIN_OVERRIDE=all — всем записям (побочка: приложение не сможет попросить свою частоту)
if [ "$WIN_OVERRIDE" = "all" ]; then
  sed -i -E -e '/<item/ s/ enableWinOverride="[a-z]+"//' \
            -e '/<item/ s|(<item [^>]*)/>|\1 enableWinOverride="false" />|' "$DST"
  log "оконный оверрайд запрещён всем: записей $(grep -o 'enableWinOverride=\"false\"' "$DST" | wc -l)"
fi

# --- камера: снять оба зажима у камерных приложений -----------------------
# Зажимов два и они независимы:
#   1) getSpecialLowRefreshRateId() при открытой камере отдаёт rateId 2 (60 Гц)
#      — лечится тегом <cameraOverride package="X"/>;
#   2) ревизия по запросу окна (в логе "revised to win request") — лечится
#      атрибутом enableWinOverride="false" у записи приложения.
# Плюс highLightCameraRate: без него на высокой яркости камера уходит в 90 Гц.
if [ "$CAMERA_165" = "1" ]; then
  # список: ручной + встроенный на случай первой загрузки + собранный на устройстве
  CAM="$CAMERA_PKGS"
  [ -f "$MODDIR/camera_pkgs.default" ] && CAM="$CAM $(cat "$MODDIR/camera_pkgs.default")"
  # собранный на устройстве список лежит вне модуля — переживает обновление модуля
  [ -f "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ] && CAM="$CAM $(cat "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}")"
  [ -f "$MODDIR/camera_pkgs.auto" ] && CAM="$CAM $(cat "$MODDIR/camera_pkgs.auto")"
  # без дубликатов: ручной список и автоматический пересекаются
  CAM=$(for x in $CAM; do echo "$x"; done | sort -u)

  DEF=$(grep -m1 -oE 'defaultRateId="[0-9-]+"' "$DST" | sed -e 's/.*="//' -e 's/"//')
  [ -z "$DEF" ] && DEF="1-3-2-7"

  SEDF="$PATCH_DIR/pkg.sed"
  : > "$SEDF"
  ins=""; n_over=0; n_item=0; n_new=0
  for p in $CAM; do
    [ -z "$p" ] && continue
    [ "$p" = "android" ] && continue
    if ! grep -q "<cameraOverride package=\"$p\"" "$DST"; then
      ins="$ins<cameraOverride package=\"$p\" />"
      n_over=$((n_over + 1))
    fi
    if grep -q "<item package=\"$p\"" "$DST"; then
      if [ "$WIN_OVERRIDE" = "camera" ]; then
        printf '/<item package="%s"/{\ns/ enableWinOverride="[a-z]*"//\ns|(<item [^>]*)/>|\\1 enableWinOverride="false" />|\n}\n' "$p" >> "$SEDF"
        n_item=$((n_item + 1))
      fi
    else
      ins="$ins<item package=\"$p\" rateId=\"$DEF\" enableWinOverride=\"false\" />"
      n_new=$((n_new + 1))
    fi
  done

  [ -s "$SEDF" ] && sed -i -E -f "$SEDF" "$DST"
  [ -n "$ins" ] && sed -i -E "s|(<config [^>]*/>)|\\1$ins|" "$DST"
  rm -f "$SEDF"

  sed -i -E -e 's| highLightCameraRate="[0-9]+"||' -e 's|<config |<config highLightCameraRate="7" |' "$DST"
  log "камера: cameraOverride +$n_over, флаг проставлен $n_item, новых записей $n_new"
fi

# --- проверяем результат -------------------------------------------------
SRC_LINES=$(wc -l < "$SRC")
DST_LINES=$(wc -l < "$DST")
if [ "$SRC_LINES" != "$DST_LINES" ]; then
  log "ОТМЕНА: число строк не совпало ($SRC_LINES -> $DST_LINES)"
  rm -f "$DST"
  exit 0
fi

CHANGED=$(grep -cE ' rateId="[0-9]-[0-9]-[0-9]-7"' "$DST")
if [ "${CHANGED:-0}" -lt 1 ]; then
  log "ОТМЕНА: патч не дал ни одной записи 165 Гц"
  rm -f "$DST"
  exit 0
fi

if ! grep -qE '<config [^>]*defaultRateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$DST"; then
  log "ОТМЕНА: строка <config> с defaultRateId испорчена или не найдена"
  rm -f "$DST"
  exit 0
fi

# --- права и SELinux -----------------------------------------------------
chown 0:0 "$DST"
chmod 0644 "$DST"
CTX=$(ls -Zd "$SRC" 2>/dev/null | sed -E 's/^([^ ]+).*/\1/')
case "$CTX" in
  u:object_r:*) chcon "$CTX" "$DST" 2>>"$LOG" || log "chcon $CTX не сработал" ;;
  *)            chcon u:object_r:system_file:s0 "$DST" 2>>"$LOG" || log "chcon по умолчанию не сработал" ;;
esac

# --- монтируем -----------------------------------------------------------
if mount -o bind "$DST" "$SRC" 2>>"$LOG" || mount --bind "$DST" "$SRC" 2>>"$LOG"; then
  log "подменён $SRC (записей 165 Гц: $CHANGED из $SRC_ITEMS)"
  echo "$SRC" > "$STATE"
else
  log "ОШИБКА: mount --bind не удался"
  exit 0
fi

# --- предупреждение про RUS-копию в /data --------------------------------
if [ -f /data/system/refresh_rate_config.xml ]; then
  log "внимание: есть /data/system/refresh_rate_config.xml (RUS). Версия в нашем файле поднята до 20991231, система должна выбрать наш."
fi

exit 0

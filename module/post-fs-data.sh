#!/system/bin/sh
# OnePlus15-165HZ-LTPO — builds and bind-mounts a patched refresh_rate_config.xml.
#
# The patch is generated on the device from the live file, so the module is not
# tied to a firmware version. If the file is missing, does not look like a
# refresh_rate_config, or the patch produces nothing, nothing gets mounted.

MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"
STATE="$MODDIR/.mounted"

log() { echo "[$(date '+%m-%d %H:%M:%S')] post-fs-data: $*" >> "$LOG"; }

rm -f "$STATE"
: > "$LOG"

FORCE_ALL=1
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"

# --- locate the stock config ---------------------------------------------
SRC=""
for p in /my_product/etc /my_stock/etc /product/etc /system/etc /vendor/etc; do
  if [ -f "$p/refresh_rate_config.xml" ]; then SRC="$p/refresh_rate_config.xml"; break; fi
done
if [ -z "$SRC" ]; then
  log "refresh_rate_config.xml not found — nothing to do"
  exit 0
fi
log "source: $SRC"

# --- make sure it really is that format ----------------------------------
if ! grep -q "<refresh_rate_config" "$SRC"; then
  log "ABORT: no <refresh_rate_config tag in $SRC"
  exit 0
fi
SRC_ITEMS=$(grep -cE 'rateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$SRC")
if [ "${SRC_ITEMS:-0}" -lt 10 ]; then
  log "ABORT: rateId format not recognised (found $SRC_ITEMS entries)"
  exit 0
fi

# already our file? (the script was run again on top of a live mount)
if grep -q 'version="20991231"' "$SRC"; then
  log "ABORT: $SRC already holds our patched file, not patching twice"
  echo "$SRC" > "$STATE"
  exit 0
fi

# --- generate ------------------------------------------------------------
PATCH_DIR="$MODDIR/patched"
DST="$PATCH_DIR/refresh_rate_config.xml"
mkdir -p "$PATCH_DIR"
rm -f "$DST"

if [ "$FORCE_ALL" = "1" ]; then
  RULES="$MODDIR/sed/force.sed"
else
  RULES="$MODDIR/sed/respect.sed"
fi
log "rules: $RULES (FORCE_ALL=$FORCE_ALL)"

if ! sed -E -f "$RULES" "$SRC" > "$DST" 2>>"$LOG"; then
  log "ABORT: sed failed"
  rm -f "$DST"
  exit 0
fi

# --- stop apps from pulling the rate down through the window request ------
# WIN_OVERRIDE=all — every entry (side effect: no app can request its own rate)
if [ "$WIN_OVERRIDE" = "all" ]; then
  sed -i -E -e '/<item/ s/ enableWinOverride="[a-z]+"//' \
            -e '/<item/ s|(<item [^>]*)/>|\1 enableWinOverride="false" />|' "$DST"
  log "window override disabled for every entry: $(grep -o 'enableWinOverride=\"false\"' "$DST" | wc -l) tags"
fi

# --- camera: lift both caps for camera apps ------------------------------
# There are two independent caps:
#   1) with a camera open, getSpecialLowRefreshRateId() returns rateId 2 (60 Hz)
#      — lifted by a <cameraOverride package="X"/> tag;
#   2) the window-request revision ("revised to win request" in the log)
#      — lifted by enableWinOverride="false" on the app's entry.
# Plus highLightCameraRate: without it the camera drops to 90 Hz at high brightness.
if [ "$CAMERA_165" = "1" ]; then
  # list: manual + built-in fallback for the very first boot + collected on device
  CAM="$CAMERA_PKGS"
  [ -f "$MODDIR/camera_pkgs.default" ] && CAM="$CAM $(cat "$MODDIR/camera_pkgs.default")"
  # the collected list lives outside the module so it survives a module update
  [ -f "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" ] && CAM="$CAM $(cat "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}")"
  [ -f "$MODDIR/camera_pkgs.auto" ] && CAM="$CAM $(cat "$MODDIR/camera_pkgs.auto")"
  # packages actually seen using a camera, learned by the daemon
  [ -f "${CAMERA_USED:-/data/adb/vrr_camera_used}" ] && CAM="$CAM $(cat "${CAMERA_USED:-/data/adb/vrr_camera_used}")"
  # drop duplicates: the lists overlap
  CAM=$(for x in $CAM; do echo "$x"; done | sort -u)

  DEF=$(grep -m1 -oE 'defaultRateId="[0-9-]+"' "$DST" | sed -e 's/.*="//' -e 's/"//')
  [ -z "$DEF" ] && DEF="1-3-2-7"

  SEDF="$PATCH_DIR/pkg.sed"
  : > "$SEDF"
  # Who gets enableWinOverride="false": only packages actually seen using a
  # camera, plus the manual list. The flag also blocks an app from requesting
  # its own refresh rate, so handing it to every permission holder would take
  # that away from browsers, players and maps for no reason.
  WIN=""
  [ -f "${CAMERA_USED:-/data/adb/vrr_camera_used}" ] && WIN="$(cat "${CAMERA_USED:-/data/adb/vrr_camera_used}")"
  WIN="$WIN $CAMERA_PKGS"

  ins=""; n_over=0; n_item=0; n_new=0
  for p in $CAM; do
    [ -z "$p" ] && continue
    [ "$p" = "android" ] && continue

    # cameraOverride is free: it only matters while the app holds a camera
    if ! grep -q "<cameraOverride package=\"$p\"" "$DST"; then
      ins="$ins<cameraOverride package=\"$p\" />"
      n_over=$((n_over + 1))
    fi

    needs_flag=0
    for w in $WIN; do [ "$w" = "$p" ] && needs_flag=1 && break; done
    [ "$WIN_OVERRIDE" = "camera" ] || needs_flag=0

    if grep -q "<item package=\"$p\"" "$DST"; then
      if [ "$needs_flag" = "1" ]; then
        printf '/<item package="%s"/{\ns/ enableWinOverride="[a-z]*"//\ns|(<item [^>]*)/>|\\1 enableWinOverride="false" />|\n}\n' "$p" >> "$SEDF"
        n_item=$((n_item + 1))
      fi
    elif [ "$needs_flag" = "1" ]; then
      ins="$ins<item package=\"$p\" rateId=\"$DEF\" enableWinOverride=\"false\" />"
      n_new=$((n_new + 1))
    fi
  done

  [ -s "$SEDF" ] && sed -i -E -f "$SEDF" "$DST"
  [ -n "$ins" ] && sed -i -E "s|(<config [^>]*/>)|\\1$ins|" "$DST"
  rm -f "$SEDF"

  sed -i -E -e 's| highLightCameraRate="[0-9]+"||' -e 's|<config |<config highLightCameraRate="7" |' "$DST"
  log "camera: cameraOverride +$n_over (all permission holders), enableWinOverride on $n_item, new entries $n_new (actual camera users)"
fi

# --- validate the result -------------------------------------------------
SRC_LINES=$(wc -l < "$SRC")
DST_LINES=$(wc -l < "$DST")
if [ "$SRC_LINES" != "$DST_LINES" ]; then
  log "ABORT: line count changed ($SRC_LINES -> $DST_LINES)"
  rm -f "$DST"
  exit 0
fi

CHANGED=$(grep -cE ' rateId="[0-9]-[0-9]-[0-9]-7"' "$DST")
if [ "${CHANGED:-0}" -lt 1 ]; then
  log "ABORT: the patch produced no 165 Hz entries"
  rm -f "$DST"
  exit 0
fi

if ! grep -qE '<config [^>]*defaultRateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$DST"; then
  log "ABORT: the <config> line with defaultRateId is damaged or missing"
  rm -f "$DST"
  exit 0
fi

# --- ownership and SELinux -----------------------------------------------
chown 0:0 "$DST"
chmod 0644 "$DST"
CTX=$(ls -Zd "$SRC" 2>/dev/null | sed -E 's/^([^ ]+).*/\1/')
case "$CTX" in
  u:object_r:*) chcon "$CTX" "$DST" 2>>"$LOG" || log "chcon $CTX failed" ;;
  *)            chcon u:object_r:system_file:s0 "$DST" 2>>"$LOG" || log "default chcon failed" ;;
esac

# --- mount ---------------------------------------------------------------
if mount -o bind "$DST" "$SRC" 2>>"$LOG" || mount --bind "$DST" "$SRC" 2>>"$LOG"; then
  log "mounted over $SRC (165 Hz entries: $CHANGED of $SRC_ITEMS)"
  echo "$SRC" > "$STATE"
else
  log "ERROR: bind mount failed"
  exit 0
fi

# --- warn about a RUS copy in /data --------------------------------------
if [ -f /data/system/refresh_rate_config.xml ]; then
  log "note: /data/system/refresh_rate_config.xml exists (RUS update). Our file claims version 20991231, so the system should prefer ours."
fi

exit 0

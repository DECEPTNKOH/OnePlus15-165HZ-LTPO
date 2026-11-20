#!/system/bin/sh
# Generate from a stock snapshot; validate both XML documents before mounting.
MODDIR=${0%/*}
LOG="$MODDIR/vrrd.log"
STATE="$MODDIR/.mounted"
log() { echo "[$(date '+%m-%d %H:%M:%S')] post-fs-data: $*" >> "$LOG"; }
abort() { log "ABORT: $*"; exit 1; }
run() { "$@" 2>>"$LOG" || abort "command failed: $*"; }
rm -f "$STATE"
: > "$LOG"
FORCE_ALL=1
WIN_OVERRIDE=camera
CAMERA_165=1
CAMERA_PKGS=com.oplus.camera
[ -f "$MODDIR/vrr.conf" ] && . "$MODDIR/vrr.conf"
set -f
case "$FORCE_ALL:$CAMERA_165:$WIN_OVERRIDE" in
  [01]:[01]:camera|[01]:[01]:all|[01]:[01]:off) ;;
  *) abort "invalid patch settings" ;;
esac
SRC=""
for p in /my_product/etc /my_stock/etc /product/etc /system/etc /vendor/etc; do
  if [ -f "$p/refresh_rate_config.xml" ]; then SRC="$p/refresh_rate_config.xml"; break; fi
done
[ -n "$SRC" ] || abort "stock config not found"
if grep -q 'version="20991231"' "$SRC"; then abort "source already patched; refusing to claim a mount"; fi
[ -s "$MODDIR/bin/xmlguard.jar" ] && [ -f "$MODDIR/xmlguard.sh" ] || abort "XML guard missing; build it before packaging"
PATCH_DIR="$MODDIR/patched"
run mkdir -p "$PATCH_DIR"
W="$PATCH_DIR/work.$$"
run mkdir "$W"
trap 'rm -rf "$W"' 0
S="$W/source.xml"
D="$W/result.xml"
run cp "$SRC" "$S"
if [ "$FORCE_ALL" = 1 ]; then RULES="$MODDIR/sed/force.sed"; else RULES="$MODDIR/sed/respect.sed"; fi
run sed -E -f "$RULES" "$S" > "$D"
if [ "$WIN_OVERRIDE" = all ]; then
  run sed -i -E -e '/<item/ s/ enableWinOverride="[a-z]+"//' \
    -e '/<item/ s|(<item [^>]*)/>|\1 enableWinOverride="false" />|' "$D"
fi
# Package lists are data, not regular expressions or XML fragments.
read_list() { sed 's/#.*$//' "$1"; }
validate_list() {
  for pkg in $1; do
    [ "$pkg" = android ] && continue
    printf '%s\n' "$pkg" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*$' || return 1
    printf '%s\n' "$pkg"
  done
}
if [ "$CAMERA_165" = 1 ]; then
  CAM="$CAMERA_PKGS"
  WIN="$CAMERA_PKGS"
  for f in "$MODDIR/camera_pkgs.default" "${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}" "$MODDIR/camera_pkgs.auto"; do
    if [ -f "$f" ]; then more=$(read_list "$f") || abort "cannot read $f"; CAM="$CAM $more"; fi
  done
  f="${CAMERA_USED:-/data/adb/vrr_camera_used}"
  if [ -f "$f" ]; then more=$(read_list "$f") || abort "cannot read $f"; CAM="$CAM $more"; WIN="$WIN $more"; fi
  CAM=$(validate_list "$CAM") || abort "invalid camera package list"
  WIN=$(validate_list "$WIN") || abort "invalid window package list"
  CAM=$(printf '%s\n' "$CAM" | sort -u) || abort "cannot sort camera list"
  DEF=$(grep -m1 -oE 'defaultRateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$D" | sed 's/.*="//;s/"//')
  [ -n "$DEF" ] || abort "defaultRateId not found"
  : > "$W/pkg.sed" || abort "cannot create sed rules"
  : > "$W/expected" || abort "cannot create insertion manifest"
  ins=""
  for pkg in $CAM; do
    if ! grep -Fq "<cameraOverride package=\"$pkg\"" "$D"; then
      tag="<cameraOverride package=\"$pkg\" />"
      ins="$ins$tag"
      printf '%s\n' "$tag" >> "$W/expected" || abort "cannot record insertion"
    fi
    needs=0
    if [ "$WIN_OVERRIDE" = camera ]; then
      for wanted in $WIN; do [ "$wanted" = "$pkg" ] && needs=1 && break; done
    fi
    [ "$needs" = 1 ] || continue
    if grep -Fq "<item package=\"$pkg\"" "$D"; then
      escaped=$(printf '%s\n' "$pkg" | sed 's/[.]/\\./g') || abort "cannot escape package"
      printf '/<item package="%s"/{\ns/ enableWinOverride="[a-z]*"//\ns|(<item [^>]*)/>|\\1 enableWinOverride="false" />|\n}\n' "$escaped" >> "$W/pkg.sed" || abort "cannot write rules"
    else
      tag="<item package=\"$pkg\" rateId=\"$DEF\" enableWinOverride=\"false\" />"
      ins="$ins$tag"
      printf '%s\n' "$tag" >> "$W/expected" || abort "cannot record insertion"
    fi
  done
  if [ -s "$W/pkg.sed" ]; then run sed -i -E -f "$W/pkg.sed" "$D"; fi
  if [ -n "$ins" ]; then run sed -i -E "s|(<config [^>]*/>)|\\1$ins|" "$D"; fi
  run sed -i -E -e 's| highLightCameraRate="[0-9]+"||' -e 's|<config |<config highLightCameraRate="7" |' "$D"
  while IFS= read -r tag; do grep -Fq "$tag" "$D" || abort "expected insertion missing"; done < "$W/expected"
  grep -q 'highLightCameraRate="7"' "$D" || abort "camera brightness override missing"
  if [ "$WIN_OVERRIDE" = camera ]; then
    for pkg in $WIN; do
      grep -F "<item package=\"$pkg\"" "$D" | grep -Fq 'enableWinOverride="false"' || abort "window override missing for $pkg"
    done
  fi
fi
# Mandatory real parser: syntax + preservation checks on original and result.
if ! sh "$MODDIR/xmlguard.sh" compare "$S" "$D" >>"$LOG" 2>&1; then abort "XML guard rejected patch or failed"; fi
run chown 0:0 "$D"
run chmod 0644 "$D"
CTX=$(ls -Zd "$SRC" 2>/dev/null | sed -E 's/^([^ ]+).*/\1/')
case "$CTX" in u:object_r:*) run chcon "$CTX" "$D" ;; *) abort "cannot determine source SELinux context" ;; esac
DST="$PATCH_DIR/refresh_rate_config.xml"
run mv -f "$D" "$DST"
printf '%s\n' "$SRC" > "$W/mounted" || abort "cannot prepare mount marker"
if mount -o bind "$DST" "$SRC" 2>>"$LOG" || mount --bind "$DST" "$SRC" 2>>"$LOG"; then
  if ! mv "$W/mounted" "$STATE"; then
    umount "$SRC" 2>>"$LOG" || log "ERROR: rollback unmount failed"
    abort "cannot publish mount marker"
  fi
  log "validated patch mounted over $SRC"
else
  abort "bind mount failed"
fi

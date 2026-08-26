#!/system/bin/sh
# Collects the packages that request the camera permission.
# The result is stored outside the module and used the next time the patch is built.
MODDIR=${0%/*}
OUT="${CAMERA_LIST:-/data/adb/vrr_camera_pkgs}"
TMP="$MODDIR/.camscan.tmp"
mkdir -p "$(dirname "$OUT")" 2>/dev/null

dumpsys package 2>/dev/null | grep -E "^  Package \[|android\.permission\.CAMERA" > "$TMP" || exit 1

pkg=""
: > "$TMP.list"
while IFS= read -r ln; do
  case "$ln" in
    *"Package ["*) pkg=$(echo "$ln" | sed -E 's/.*Package \[([^]]*)\].*/\1/') ;;
    *android.permission.CAMERA*)
      if [ -n "$pkg" ] && [ "$pkg" != "android" ]; then echo "$pkg" >> "$TMP.list"; fi
      pkg="" ;;
  esac
done < "$TMP"

if [ -s "$TMP.list" ]; then
  sort -u "$TMP.list" > "$OUT"
  echo "camera apps found: $(wc -l < "$OUT")"
else
  echo "empty result, keeping the previous list"
fi
rm -f "$TMP" "$TMP.list"

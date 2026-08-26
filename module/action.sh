#!/system/bin/sh
# The action button in the KernelSU manager.
# Rebuilds the patch from the current firmware file — useful after an OTA,
# after editing vrr.conf, or after installing new camera apps.
MODDIR=${0%/*}

echo "OnePlus15-165HZ-LTPO — rebuilding the patch"
echo

# 1. refresh the camera app list
if [ -f "$MODDIR/scan_camera_pkgs.sh" ]; then
  echo "· $(sh "$MODDIR/scan_camera_pkgs.sh" 2>&1 | tail -1)"
fi

# 2. unmount, so the stock firmware file is exposed underneath
SRC=$(cat "$MODDIR/.mounted" 2>/dev/null)
[ -z "$SRC" ] && SRC=/my_product/etc/refresh_rate_config.xml
i=0
while grep -q 'version="20991231"' "$SRC" 2>/dev/null && [ $i -lt 5 ]; do
  umount "$SRC" 2>/dev/null || break
  i=$((i + 1))
done
if grep -q 'version="20991231"' "$SRC" 2>/dev/null; then
  echo "· could not unmount $SRC — a reboot is required"
  exit 1
fi
echo "· unmounted, the stock firmware file is exposed"

# 3. rebuild and mount again
sh "$MODDIR/post-fs-data.sh"

echo
if [ -f "$MODDIR/.mounted" ]; then
  echo "Done. Result:"
  D="$MODDIR/patched/refresh_rate_config.xml"
  echo "  165 Hz entries:      $(grep -o ' rateId="[0-9]-[0-9]-[0-9]-7"' "$D" 2>/dev/null | wc -l)"
  echo "  cameraOverride tags: $(grep -o '<cameraOverride' "$D" 2>/dev/null | wc -l)"
  echo "  enableWinOverride:   $(grep -o 'enableWinOverride="false"' "$D" 2>/dev/null | wc -l)"
  echo
  echo "The file is mounted, but the system only reads it at boot —"
  echo "reboot for the changes to take effect."
else
  echo "The patch was NOT applied. Reason from the log:"
  tail -4 "$MODDIR/vrrd.log" 2>/dev/null
fi

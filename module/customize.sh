#!/system/bin/sh
# Sourced by the root manager after extraction; no settings writes here.
[ "$BOOTMODE" = true ] || abort "Install this preview from the Android root manager, not recovery."
case "$(getprop ro.product.model):$(getprop ro.build.display.id)" in
  CPH2747:*|*:CPH2747_*) ;;
  *) abort "This preview targets OnePlus 15 CPH2747 only." ;;
esac
case "$(getprop ro.build.version.release)" in
  17) ;;
  16) ui_print "WARNING: Android 16 is untested by this fork; patch is generated from the live config and guarded. Proceeding." ;;
  *) abort "This preview targets Android 16/17 (OnePlus 15)." ;;
esac
# Не сосуществовать с другим 165Hz-модулем (двойной mount + два демона).
for m in /data/adb/modules/*/module.prop; do
  [ -f "$m" ] || continue
  case "$m" in */OnePlus15-165HZ-LTPO/*) continue ;; esac
  if grep -qiE 'id=.*oneplus15.*165|name=.*oneplus.*165' "$m" 2>/dev/null; then
    abort "Conflicting 165 Hz module detected: $(dirname "$m"). Remove it first."
  fi
done
[ -s "$MODPATH/bin/xmlguard.jar" ] || abort "Missing XML validator JAR."
[ -s "$MODPATH/SHA256SUMS" ] || abort "Missing archive checksums."
(cd "$MODPATH" && sha256sum -c SHA256SUMS) >/dev/null 2>&1 || abort "Archive checksum verification failed."
[ -x /system/bin/app_process ] && [ -x /system/bin/timeout ] || abort "Required Android runtime tools missing."
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH"/*.sh; do set_perm "$f" 0 0 0755; done
set_perm "$MODPATH/bin/xmlguard.jar" 0 0 0444
export MODULE_HOT_INSTALL_REQUEST=false
OVRR=/data/adb/oneplus15-vrr-state/vrr.conf
if [ ! -f "$OVRR" ]; then
  mkdir -p /data/adb/oneplus15-vrr-state
  {
    echo "# User overrides for OnePlus15-165HZ-LTPO (survives module updates)."
    echo "# Uncomment and edit, then reboot. Example:"
    echo "#IDLE_TIMEOUT=3"
    echo "#KEEP_ACTIVE_PKGS=\"com.example.game\""
  } > "$OVRR"
  chmod 0600 "$OVRR"
fi
ui_print "User overrides: /data/adb/oneplus15-vrr-state/vrr.conf (kept across updates)."
ui_print "DECEPTNKOH experimental preview. Reboot required."
ui_print "Defaults replace vrr.conf; keep your previous backup."
ui_print "The first daemon start saves the current setting, not an unknown pre-v1.8 value."

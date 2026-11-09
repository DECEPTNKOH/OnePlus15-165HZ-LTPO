#!/system/bin/sh
# Sourced by the root manager after extraction; no settings writes here.
[ "$BOOTMODE" = true ] || abort "Install this preview from the Android root manager, not recovery."
case "$(getprop ro.product.model):$(getprop ro.build.display.id)" in
  CPH2747:*|*:CPH2747_*) ;;
  *) abort "This preview targets OnePlus 15 CPH2747 only." ;;
esac
[ "$(getprop ro.build.version.release)" = 17 ] || abort "This preview targets Android 17 only."
[ -s "$MODPATH/bin/xmlguard.jar" ] || abort "Missing XML validator JAR."
[ -s "$MODPATH/SHA256SUMS" ] || abort "Missing archive checksums."
(cd "$MODPATH" && sha256sum -c SHA256SUMS) >/dev/null 2>&1 || abort "Archive checksum verification failed."
[ -x /system/bin/app_process ] && [ -x /system/bin/timeout ] || abort "Required Android runtime tools missing."
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH"/*.sh; do set_perm "$f" 0 0 0755; done
set_perm "$MODPATH/bin/xmlguard.jar" 0 0 0444
export MODULE_HOT_INSTALL_REQUEST=false
ui_print "DECEPTNKOH experimental preview. Reboot required."
ui_print "Defaults replace vrr.conf; keep your previous backup."
ui_print "The first daemon start saves the current setting, not an unknown pre-v1.8 value."

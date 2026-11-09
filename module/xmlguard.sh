#!/system/bin/sh
MODDIR=${0%/*}
JAR="$MODDIR/bin/xmlguard.jar"
[ -s "$JAR" ] || { echo "XML_GUARD_ERROR: missing xmlguard.jar" >&2; exit 1; }
[ -x /system/bin/app_process ] && [ -x /system/bin/timeout ] || exit 1
CLASSPATH="$JAR" /system/bin/timeout 8 /system/bin/app_process /system/bin XmlGuard "$@"

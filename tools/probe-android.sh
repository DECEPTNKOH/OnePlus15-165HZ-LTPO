#!/system/bin/sh
set -u
JAR=$1
T=/data/adb/oneplus15-vrr-backups/xmlguard-probe-$$
umask 077
mkdir -p "$T" || exit 1
trap 'rm -rf "$T"' 0
cp "$JAR" "$T/xmlguard.jar" || exit 1
chmod 0444 "$T/xmlguard.jar" || exit 1
printf '%s\n' '<refresh_rate_config version="1"><config defaultRateId="1-1-2-3" defaultRateId="1-1-2-3"/><item package="com.example.app" rateId="1-1-2-3"/></refresh_rate_config>' > "$T/bad.xml"
echo '=== CURRENT XML ==='
CLASSPATH="$T/xmlguard.jar" /system/bin/timeout 10 /system/bin/app_process /system/bin XmlGuard check /my_product/etc/refresh_rate_config.xml
GOOD=$?
echo "CURRENT_XML_EXIT=$GOOD (expected 0)"
echo '=== DUPLICATE ATTRIBUTE ==='
CLASSPATH="$T/xmlguard.jar" /system/bin/timeout 10 /system/bin/app_process /system/bin XmlGuard check "$T/bad.xml"
BAD=$?
echo "BAD_XML_EXIT=$BAD (expected 1)"
[ "$GOOD" = 0 ] && [ "$BAD" = 1 ]

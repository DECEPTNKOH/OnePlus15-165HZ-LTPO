#!/system/bin/sh
# Do not signal a PID from the legacy .vrrd.pid file: it may belong to an
# unrelated process, including after a reboot. Removal requires a reboot;
# until then an existing daemon may still change the setting.
# A verified stop protocol will replace this conservative fallback.

cmd settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null || settings put secure oplus_customize_screen_refresh_rate 7 2>/dev/null

exit 0

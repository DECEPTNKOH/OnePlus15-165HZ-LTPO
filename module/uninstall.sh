#!/system/bin/sh
# Request cooperative shutdown. Never signal a PID from a file.
MODDIR=${0%/*}
PIDFILE="$MODDIR/.vrrd.pid"
say() { echo "uninstall: $*" >> "$MODDIR/vrrd.log"; }
[ -r "$MODDIR/lifecycle.sh" ] && [ -r "$MODDIR/settings-state.sh" ] || exit 1
. "$MODDIR/lifecycle.sh"
. "$MODDIR/settings-state.sh"
: > "$MODDIR/stop" || exit 1
i=0
while :; do
  vrr_acquire
  rc=$?
  [ "$rc" = 0 ] && break
  if [ "$rc" != 1 ] || [ "$i" -ge 15 ]; then
    say "ERROR: cannot acquire lifecycle lock; baseline retained"
    exit 1
  fi
  sleep 1
  i=$((i + 1))
done
if [ ! -e "$VRR_BASELINE" ] && [ ! -L "$VRR_BASELINE" ]; then
  say "no saved baseline; leaving setting unchanged"
  exit 0
fi
if vrr_baseline_restore; then
  rm -f "$VRR_BASELINE" || exit 1
  say "baseline restored and snapshot retired"
else
  say "ERROR: restore failed; baseline retained at $VRR_BASELINE"
  # Оставляем автономный recovery-скрипт вне модуля: настройку можно вернуть
  # позже даже после удаления каталога модуля.
  (
    umask 077
    cat > "$VRR_STATE_DIR/restore.sh" <<'VRR_EOF'
#!/system/bin/sh
# Ручное восстановление. Запуск от root:
#   su -c sh /data/adb/oneplus15-vrr-state/restore.sh
DIR=${VRR_STATE_DIR:-/data/adb/oneplus15-vrr-state}
[ -f "$DIR/baseline" ] || { echo "no baseline snapshot"; exit 1; }
{ read -r schema; read -r user; read -r value; read -r origin; } < "$DIR/baseline"
[ "$schema" = v1 ] || { echo "bad snapshot"; exit 1; }
case "$user" in ""|*[!0-9]*) echo "bad user"; exit 1 ;; esac
key=oplus_customize_screen_refresh_rate
if [ "$value" = null ]; then
  cmd settings --user "$user" delete secure "$key"
else
  case "$value" in ""|*[!0-9]*) echo "bad value"; exit 1 ;; esac
  cmd settings --user "$user" put secure "$key" "$value"
fi
echo "restored user=$user value=$value"
VRR_EOF
    chmod 0700 "$VRR_STATE_DIR/restore.sh"
  ) && say "wrote recovery script: $VRR_STATE_DIR/restore.sh"
  exit 1
fi

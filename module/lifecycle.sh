#!/system/bin/sh
# Source from vrrd.sh. FD 9 owns the kernel lock; never unlink its inode.
VRR_OWNED=0
vrr_flock() {
  if [ -n "$VRR_BUSYBOX" ]; then "$VRR_BUSYBOX" flock "$@"; else flock "$@"; fi
}
vrr_acquire() {
  VRR_BUSYBOX=""
  if ! command -v flock >/dev/null 2>&1; then
    for b in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
      if [ -x "$b" ] && "$b" --list 2>/dev/null | grep -qx flock; then
        VRR_BUSYBOX="$b"; break
      fi
    done
    if [ -z "$VRR_BUSYBOX" ]; then say "ERROR: flock unavailable; refusing unlocked startup"; return 2; fi
  fi
  exec 9>>"$MODDIR/.vrrd.lock" || return 2
  # Android mksh does not automatically export FD 9 to external commands.
  # Duplicate it onto stdin; the shell keeps the same open file on FD 9.
  if ! vrr_flock -n 0 <&9; then
    exec 9>&-
    say "daemon lock busy or unavailable; not starting"
    return 1
  fi
  VRR_BOOT=$(cat /proc/sys/kernel/random/boot_id) || { exec 9>&-; return 2; }
  VRR_START=$(sed 's/^.*) //' "/proc/$$/stat" | awk '{print $20}')
  case "$VRR_START" in ""|*[!0-9]*) exec 9>&-; return 2 ;; esac
  VRR_TOKEN="$$ $VRR_BOOT $VRR_START"
  VRR_OWNED=1
  trap vrr_release 0
  printf '%s\n' "$VRR_TOKEN" > "$MODDIR/.vrrd.identity" || return 2
  printf '%s\n' "$$" > "$PIDFILE" || return 2
}
vrr_release() {
  [ "$VRR_OWNED" = "1" ] || return 0
  # Keep the lock held until metadata cleanup is complete.
  if [ "$(cat "$MODDIR/.vrrd.identity" 2>/dev/null)" = "$VRR_TOKEN" ]; then
    rm -f "$MODDIR/.vrrd.identity" "$PIDFILE"
  fi
  VRR_OWNED=0
  exec 9>&-
}

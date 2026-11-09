#!/system/bin/sh
# Source under the daemon lifecycle lock. Never source saved data as shell code.
VRR_STATE_DIR=${VRR_STATE_DIR:-/data/adb/oneplus15-vrr-state}
VRR_BASELINE="$VRR_STATE_DIR/baseline"
VRR_KEY=oplus_customize_screen_refresh_rate
VRR_READY=0
vrr_number() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; }
vrr_value_valid() { [ "$1" = null ] || vrr_number "$1"; }
vrr_settings() {
  cmd settings --user "$VRR_USER" "$@" 2>/dev/null ||
    settings --user "$VRR_USER" "$@" 2>/dev/null
}
vrr_baseline_load() {
  VRR_READY=0
  [ ! -L "$VRR_STATE_DIR" ] && [ ! -L "$VRR_BASELINE" ] || return 1
  [ -f "$VRR_BASELINE" ] || return 1
  {
    IFS= read -r schema && IFS= read -r VRR_USER &&
    IFS= read -r VRR_VALUE && IFS= read -r origin
  } < "$VRR_BASELINE" || return 1
  [ "$schema" = v1 ] && [ "$origin" = observed-before-first-write ] || return 1
  vrr_number "$VRR_USER" && vrr_value_valid "$VRR_VALUE" || return 1
  VRR_READY=1
}
vrr_baseline_prepare() {
  # Existing snapshots survive restart and upgrade; never overwrite them.
  if [ -e "$VRR_BASELINE" ] || [ -L "$VRR_BASELINE" ]; then
    vrr_baseline_load
    return $?
  fi
  VRR_READY=0
  [ ! -L "$VRR_STATE_DIR" ] || return 1
  VRR_USER=$(cmd activity get-current-user 2>/dev/null) ||
    VRR_USER=$(am get-current-user 2>/dev/null) || return 1
  vrr_number "$VRR_USER" || return 1
  VRR_VALUE=$(vrr_settings get secure "$VRR_KEY") || return 1
  vrr_value_valid "$VRR_VALUE" || return 1
  (
    umask 077
    mkdir -p "$VRR_STATE_DIR" || exit 1
    chmod 0700 "$VRR_STATE_DIR" || exit 1
    tmp="$VRR_STATE_DIR/.baseline.$$"
    trap 'rm -f "$tmp"' 0
    printf 'v1\n%s\n%s\nobserved-before-first-write\n' "$VRR_USER" "$VRR_VALUE" > "$tmp" || exit 1
    chmod 0600 "$tmp" && mv "$tmp" "$VRR_BASELINE"
  ) || return 1
  vrr_baseline_load
}
vrr_mode_write() {
  [ "$VRR_READY" = 1 ] && vrr_number "$1" || return 1
  vrr_settings put secure "$VRR_KEY" "$1"
}
vrr_baseline_restore() {
  # Re-read and validate the durable snapshot, including the original user ID.
  vrr_baseline_load || return 1
  if [ "$VRR_VALUE" = null ]; then
    vrr_settings delete secure "$VRR_KEY" >/dev/null || return 1
  else
    vrr_settings put secure "$VRR_KEY" "$VRR_VALUE" || return 1
  fi
  actual=$(vrr_settings get secure "$VRR_KEY") || return 1
  [ "$actual" = "$VRR_VALUE" ]
}

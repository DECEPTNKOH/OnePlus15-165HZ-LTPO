#!/system/bin/sh
# Source under the daemon lifecycle lock. Never source saved data as shell code.
VRR_STATE_DIR=${VRR_STATE_DIR:-/data/adb/oneplus15-vrr-state}
VRR_BASELINE="$VRR_STATE_DIR/baseline"
VRR_KEY=oplus_customize_screen_refresh_rate
VRR_READY=0

vrr_number() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; }
vrr_norm_value() {
  case "$1" in
    ""|null) printf '%s\n' "null" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
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
  if [ -e "$VRR_BASELINE" ] || [ -L "$VRR_BASELINE" ]; then
    vrr_baseline_load
    return $?
  fi
  VRR_READY=0
  [ ! -L "$VRR_STATE_DIR" ] || return 1
  VRR_USER=$(cmd activity get-current-user 2>/dev/null) ||
    VRR_USER=$(am get-current-user 2>/dev/null) || return 1
  vrr_number "$VRR_USER" || return 1
  raw_val=$(vrr_settings get secure "$VRR_KEY") || return 1
  VRR_VALUE=$(vrr_norm_value "$raw_val")
  vrr_value_valid "$VRR_VALUE" || return 1

  # Пропускаем снапшот только при наличии write-ahead dirty-маркера (реальный
  # остаток демона). Совпавшее значение БЕЗ маркера — легитимный выбор пользователя
  # (например стоковая "1") и снапшотится нормально. При маркере без снапшота
  # fallback в null, чтобы uninstall сбросил ключ к системному дефолту.
  if [ "${VRR_SKIP_DIRTY_BASELINE:-0}" = "1" ] && [ -f "$VRR_STATE_DIR/dirty" ] &&
     { [ "$VRR_VALUE" = "${ACTIVE_MODE:-7}" ] || [ "$VRR_VALUE" = "${IDLE_MODE:-1}" ]; }; then
    command -v say >/dev/null 2>&1 && say "warning: dirty marker present and $VRR_KEY=$VRR_VALUE matches daemon mode; baseline falls back to null (system default)"
    VRR_VALUE=null
  fi

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

vrr_dirty_mark() {
  ( umask 077; mkdir -p "$VRR_STATE_DIR" && chmod 0700 "$VRR_STATE_DIR" && : > "$VRR_STATE_DIR/dirty" )
}

vrr_mode_write() {
  [ "$VRR_READY" = 1 ] && vrr_number "$1" || return 1
  # Write-ahead маркер: краш до restore обнаруживается на следующей загрузке.
  vrr_dirty_mark || return 1
  vrr_settings put secure "$VRR_KEY" "$1"
}

vrr_baseline_restore() {
  [ -f "$VRR_BASELINE" ] || return 0
  vrr_baseline_load || return 1
  if [ "$VRR_VALUE" = null ]; then
    vrr_settings delete secure "$VRR_KEY" >/dev/null 2>&1 || true
  else
    vrr_settings put secure "$VRR_KEY" "$VRR_VALUE" || return 1
  fi
  raw_actual=$(vrr_settings get secure "$VRR_KEY") || return 1
  actual=$(vrr_norm_value "$raw_actual")
  [ "$actual" = "$VRR_VALUE" ] || return 1
  rm -f "$VRR_STATE_DIR/dirty"
}

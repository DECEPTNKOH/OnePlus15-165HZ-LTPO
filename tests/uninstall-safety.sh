#!/bin/sh
# Run on a host: sh tests/uninstall-safety.sh
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module" "$T/bin"
cp module/uninstall.sh "$T/module/uninstall.sh"
echo 11953 > "$T/module/.vrrd.pid"
cat > "$T/bin/cmd" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_RECORD"
exit 0
EOF
cp "$T/bin/cmd" "$T/bin/settings"
chmod +x "$T/bin/cmd" "$T/bin/settings"
export TEST_RECORD="$T/record"
# Override shell kill so any attempted signal is detected, not sent.
PATH="$T/bin:$PATH" sh -c '
  kill() { echo SIGNAL >> "$TEST_RECORD"; return 1; }
  export PATH TEST_RECORD
  . "$1"
' sh "$T/module/uninstall.sh"
if grep -q SIGNAL "$TEST_RECORD"; then
  echo 'FAIL: uninstall attempted to signal a legacy PID' >&2
  exit 1
fi
grep -q '^settings put secure oplus_customize_screen_refresh_rate 7$' "$TEST_RECORD"
echo 'ok: uninstall never signals a legacy PID'

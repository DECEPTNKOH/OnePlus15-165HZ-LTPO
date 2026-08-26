#!/bin/bash
# Runs the patch rules against a synthetic sample: checks that sed does exactly
# what is expected and does not break the XML. Executed by CI on every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
S=tests/sample.xml
fail() { echo "FAIL: $*" >&2; exit 1; }

for rules in module/sed/force.sed module/sed/respect.sed; do
  out=$(mktemp)
  sed -E -f "$rules" "$S" > "$out"

  [ "$(wc -l < "$S")" = "$(wc -l < "$out")" ] || fail "$rules: line count changed"
  python3 -c "import xml.etree.ElementTree as ET,sys; ET.parse('$out')" || fail "$rules: XML is broken"
  grep -q 'version="20991231"' "$out" || fail "$rules: version was not bumped"
  grep -q 'defaultRateId="1-3-2-7"' "$out" || fail "$rules: defaultRateId not rewritten"
  grep -q 'defaultMaxRate="165"' "$out" || fail "$rules: defaultMaxRate missing"
  grep -q '<item package="com.example.browser" rateId="1-3-2-7"' "$out" || fail "$rules: plain entry did not become 165"
  grep -q 'rateId="[0-9]-[0-9]-[0-9]-7".*com.example.social\|com.example.social.*rateId="7-3-2-7"' "$out" || fail "$rules: 165 entry did not get 120 as its idle slot"
  # rules must not touch comments or extremeHighRate
  grep -q '<extremeHighRate package="com.example.social" rateId="7" />' "$out" || fail "$rules: extremeHighRate was touched"

  if [ "$rules" = "module/sed/force.sed" ]; then
    grep -q '<item package="com.example.video" rateId="2-2-2-7"' "$out" || fail "force: 60 entry not raised to 165"
  else
    grep -q '<item package="com.example.video" rateId="2-2-2-2"' "$out" || fail "respect: 60 entry must stay untouched"
    grep -q '<item package="com.example.game" rateId="4-3-2-4"' "$out" || fail "respect: 144 must not become 165"
  fi

  # a second pass must change nothing
  out2=$(mktemp); sed -E -f "$rules" "$out" > "$out2"
  if [ "$rules" = "module/sed/respect.sed" ]; then
    diff -q "$out" "$out2" >/dev/null || fail "respect: rules are not idempotent"
  fi
  echo "ok: $rules"
  rm -f "$out" "$out2"
done

for f in module/*.sh; do sh -n "$f" || fail "синтаксис $f"; done
echo "ok: shell syntax"
echo "All checks passed."

#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
B="$ROOT/build/xmlguard"
mkdir -p "$B/classes" "$B/dex" "$ROOT/module/bin"
find "$B/classes" -type f -name '*.class' -delete
rm -f "$B/dex/classes.dex"
javac --release 8 -d "$B/classes" "$ROOT/tools/XmlGuard.java"
jar cf "$B/input.jar" -C "$B/classes" .
d8 --min-api 26 --output "$B/dex" "$B/input.jar"
test -s "$B/dex/classes.dex"
jar cf "$B/xmlguard.jar" -C "$B/dex" classes.dex
cp "$B/xmlguard.jar" "$ROOT/module/bin/xmlguard.jar.new"
chmod 0444 "$ROOT/module/bin/xmlguard.jar.new"
mv -f "$ROOT/module/bin/xmlguard.jar.new" "$ROOT/module/bin/xmlguard.jar"
echo XMLGUARD_BUILD_OK
sha256sum "$ROOT/module/bin/xmlguard.jar"

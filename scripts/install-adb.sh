#!/bin/sh
# Push the newest package and install it through ksud.
#   scripts/install-adb.sh [zip]
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
ZIP=${1:-$(ls -1t "$REPO"/dist/phDroid-OP15-*.zip 2>/dev/null | head -1)}
[ -f "$ZIP" ] || { echo "no package; run scripts/package.sh first"; exit 1; }
adb wait-for-device
adb push "$ZIP" /data/local/tmp/phdroid.zip >/dev/null
adb shell su -c '/data/adb/ksu/bin/ksud module install /data/local/tmp/phdroid.zip'
echo "installed; reboot to activate"

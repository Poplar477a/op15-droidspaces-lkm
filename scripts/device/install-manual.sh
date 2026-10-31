#!/system/bin/sh
# Manual install without any module manager.
#   su -c 'sh install-manual.sh /data/local/tmp/dsm'
# SRC must be the extracted module tree (module.prop at its root).
set -u
SRC=${1:-/data/local/tmp/dsm}
DST=/data/adb/modules/phdroid-op15

[ -f "$SRC/module.prop" ] || { echo "no module.prop under $SRC"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

mkdir -p "$DST" || exit 1
cp -rf "$SRC"/. "$DST"/ || exit 1
chmod 0755 "$DST"/*.sh "$DST"/tools/*.sh 2>/dev/null
chmod 0644 "$DST"/*.prop "$DST"/*.txt "$DST"/ko/*.ko 2>/dev/null
echo "installed to $DST"
ls -l "$DST" | head -20
echo
echo "load now: sh $DST/tools/confirm.sh load"

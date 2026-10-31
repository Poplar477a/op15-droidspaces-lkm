#!/system/bin/sh
# Load the modules now (same path as the boot loader, but without BOOT guards).
#   su -c 'sh /data/adb/modules/phdroid-op15/load.sh'
MODDIR=${0%/*}
PH_ACTION=1 exec sh "$MODDIR/post-fs-data.sh"

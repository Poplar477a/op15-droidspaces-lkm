#!/system/bin/sh
# Collect the previous-boot crash log and the module's own history.
#   su -c 'sh /data/adb/modules/phdroid-op15/tools/crashlog.sh'
M=/data/adb/modules/phdroid-op15

echo "===== pstore ====="
for f in /sys/fs/pstore/*; do
	[ -f "$f" ] || continue
	echo "--- $f"
	tail -n 120 "$f"
done
[ -e /sys/fs/pstore ] || echo "(no /sys/fs/pstore)"
ls -l /sys/fs/pstore 2>/dev/null

echo
echo "===== module logs ====="
for f in "$M/load.log" "$M/history.log"; do
	echo "--- $f"
	tail -n 60 "$f" 2>/dev/null
done

echo
echo "===== guards ====="
for f in blocked insmod.inflight boot_pending load.crash insmod.crash .boot_ok; do
	[ -e "$M/$f" ] && echo "present: $f"
done

echo
echo "===== last dmesg (current boot) ====="
dmesg | grep -iE 'droid_lkm|BUG:|Oops|panic|Unable to handle|watchdog|rcu' | tail -60

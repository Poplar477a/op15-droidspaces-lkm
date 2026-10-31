#!/system/bin/sh
# OP15 postcheck: run as root AFTER loading the modules
#   adb push postcheck.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/postcheck.sh'

echo "=== loaded modules ==="
grep -E '^(droid_lkm|macvlan|ip6table)' /proc/modules || echo "(none loaded)"

echo
echo "=== dmesg (module) ==="
dmesg | grep -iE 'droid_lkm|macvlan|ip6table|unknown symbol|disagrees about version|CFI failure' | tail -40

echo
echo "=== ns view ==="
ls -l /proc/self/ns/ 2>/dev/null | grep -E 'pid|ipc|mnt|uts|net|cgroup'
echo "-- unshare probes --"
unshare -p true 2>/dev/null && echo "pid ns: OK" || echo "pid ns: FAIL"
unshare -i true 2>/dev/null && echo "ipc ns: OK" || echo "ipc ns: FAIL"

echo
echo "=== devtmpfs / macvlan / ip6nat ==="
grep -q devtmpfs /proc/filesystems && echo "devtmpfs: listed" || echo "devtmpfs: absent"
ip link add ds-probe-mv link lo type macvlan mode bridge 2>/dev/null && { echo "macvlan: OK"; ip link del ds-probe-mv; } || echo "macvlan: FAIL"
ip6tables -t nat -L -n >/dev/null 2>&1 && echo "ip6 nat table: present" || echo "ip6 nat table: absent"

echo
echo "=== droidspaces check ==="
command -v droidspaces >/dev/null 2>&1 && droidspaces check 2>&1 | tail -40 || echo "droidspaces not on PATH"

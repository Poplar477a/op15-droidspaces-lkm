#!/system/bin/sh
# OP15 preflight: run as root on the phone BEFORE loading any .ko
#   adb push preflight.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/preflight.sh'

echo "=== identity ==="
echo "kernel : $(uname -r)"
case "$(uname -r)" in
*-android16-6-*) echo "kmi    : gen 6  (matches this build)" ;;
*-android16-5-*) echo "kmi    : gen 5  (build is gen 6; expect Unknown symbol)" ;;
*) echo "kmi    : unknown, check uname -r" ;;
esac
echo "device : $(getprop ro.product.device)"
echo "model  : $(getprop ro.product.model)"
echo "board  : $(getprop ro.product.board)"
echo "fp     : $(getprop ro.build.fingerprint)"
echo "root   : $(id -u) ($(id -un 2>/dev/null))"
echo "selinux: $(getenforce 2>/dev/null)"
echo "ksu/ap : $(ls -d /data/adb/ksu /data/adb/ap 2>/dev/null | tr '\n' ' ')"

echo
echo "=== module loading ==="
zcat /proc/config.gz 2>/dev/null | grep -E '^(CONFIG_MODULES=|CONFIG_MODULE_SIG=|CONFIG_MODULE_SIG_FORCE=|CONFIG_MODVERSIONS=|CONFIG_CFI_CLANG=|CONFIG_KALLSYMS_ALL=)' || echo "(no /proc/config.gz)"

echo
echo "=== namespaces / container opts ==="
zcat /proc/config.gz 2>/dev/null | grep -E '^(CONFIG_(PID_NS|IPC_NS|SYSVIPC|POSIX_MQUEUE|USER_NS|DEVTMPFS|MACVLAN|CGROUP_PIDS|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE)=|# CONFIG_(PID_NS|IPC_NS|SYSVIPC|POSIX_MQUEUE|USER_NS|DEVTMPFS|MACVLAN|CGROUP_PIDS|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE) is not set)'

echo
echo "=== current ns ==="
ls -l /proc/self/ns/

echo
echo "=== btf / filesystems ==="
ls -l /sys/kernel/btf/vmlinux 2>/dev/null || echo "no BTF"
grep -E 'devtmpfs|overlay|cgroup2|macvlan' /proc/filesystems

echo
echo "=== cgroup ==="
cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null

echo
echo "=== symbols the module resolves (MISS = fatal or degraded) ==="
for s in ksys_unshare kernel_clone kernel_clone3 copy_namespaces alloc_pid free_pid \
	 switch_task_namespaces proc_alloc_inum proc_free_inum group_send_sig_info \
	 kernel_wait4 do_mmap __do_munmap wake_q_add wake_up_q \
	 shmem_kernel_file_setup get_tree_nodev security_msg_queue_alloc \
	 _text _end kimage_voffset vmalloc_to_pfn __set_fixmap; do
	if grep -qw "$s" /proc/kallsyms 2>/dev/null; then echo "OK   $s"; else echo "MISS $s"; fi
done

echo
echo "=== droidspaces ==="
command -v droidspaces >/dev/null 2>&1 && droidspaces check 2>&1 | tail -30 || echo "droidspaces not on PATH"

#!/system/bin/sh
# One-shot confirmation of the two MUST-HAVE features.
#   read-only:  su -c 'sh /data/local/tmp/confirm.sh'
#   with load:  su -c 'sh /data/local/tmp/confirm.sh load'
set -u
KO=/data/adb/modules/phdroid-op15/ko
P=0; F=0
ok(){ P=$((P+1)); echo "PASS  $*"; }
bad(){ F=$((F+1)); echo "FAIL  $*"; }
warn(){ echo "WARN  $*"; }

REL=$(uname -r)
echo "kernel : $REL"
case "$REL" in
*-android16-6-*) echo "kmi    : gen 6 (matches this build)" ;;
*) warn "kernel is not -android16-6-; module build is gen 6" ;;
esac
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

if ! grep -q '^droid_lkm ' /proc/modules 2>/dev/null; then
	if [ "${1:-}" = load ] && [ -f "$KO/droid_lkm.ko" ]; then
		echo "loading droid_lkm ..."
		insmod "$KO/droid_lkm.ko" gate=0 mqueue=1 nspid=1 nspid_append=1 skip_sysvipc=0 no_fake_ns=0 skip_do_exit=0
		sleep 1
	else
		warn "droid_lkm not loaded (pass 'load' to insmod it)"
	fi
fi
grep -q '^droid_lkm ' /proc/modules 2>/dev/null && ok "droid_lkm loaded" || bad "droid_lkm not loaded"

[ -e /proc/self/ns/pid ] && ok "/proc/self/ns/pid exists" || bad "/proc/self/ns/pid missing"
[ -e /proc/self/ns/ipc ] && ok "/proc/self/ns/ipc exists" || bad "/proc/self/ns/ipc missing"

if command -v droidspaces >/dev/null 2>&1; then
	J=$(droidspaces check --json 2>/dev/null)
	echo "json: $J"
	case "$J" in *'"pid_ns":1'*) ok "check: pid_ns" ;; *) bad "check: pid_ns" ;; esac
	case "$J" in *'"ipc_ns":1'*) ok "check: ipc_ns" ;; *) bad "check: ipc_ns" ;; esac
	case "$J" in *'"requirements_met":1'*) ok "check: requirements_met" ;; *) bad "check: requirements_met" ;; esac
else
	warn "droidspaces not on PATH, probing unshare directly"
	unshare -p true 2>/dev/null && ok "unshare(CLONE_NEWPID)" || bad "unshare(CLONE_NEWPID)"
	unshare -i true 2>/dev/null && ok "unshare(CLONE_NEWIPC)" || bad "unshare(CLONE_NEWIPC)"
fi

echo "---- dmesg ----"
dmesg 2>/dev/null | grep -iE 'droid_lkm|unknown symbol|disagrees about version|CFI failure' | tail -25
echo
echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ] && echo "VERDICT: BASIC SUPPORT CONFIRMED" || echo "VERDICT: NOT CONFIRMED"

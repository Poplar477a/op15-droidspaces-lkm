#!/bin/bash
# Pull oplus_bsp_sched_assist.ko and disassemble update_ddl_hit_history.
#   ./disasm-ddl.sh            (device must be connected, adb root)
#   ./disasm-ddl.sh path.ko    (already pulled)
set -euo pipefail
KIT=$(cd "$(dirname "$0")" && pwd)
BIN=${LLVM_BIN:-$KIT/../ddk/root/opt/ddk/clang/clang-r536225/bin}
OBJDUMP=$BIN/llvm-objdump
NM=$BIN/llvm-nm
NAME=oplus_bsp_sched_assist
OUT=$KIT/out-ddl
mkdir -p "$OUT"

KO=${1:-}
if [ -z "$KO" ]; then
	command -v adb >/dev/null || { echo "no adb and no path given"; exit 1; }
	adb wait-for-device
	P=$(adb shell su -c "ls /vendor/lib/modules/$NAME.ko /vendor_dlkm/lib/modules/$NAME.ko /vendor/lib/modules/$NAME.ko.gz 2>/dev/null | head -1" | tr -d '\r')
	[ -n "$P" ] || { echo "module not found on device"; exit 1; }
	echo "pulling $P"
	adb pull "$P" "$OUT/$NAME.ko" >/dev/null
	KO=$OUT/$NAME.ko
	if [ "${KO##*.}" = gz ]; then gunzip -f "$KO"; KO=${KO%.gz}; fi
fi

echo "== module: $KO"
$NM "$KO" 2>/dev/null | grep -w update_ddl_hit_history || true

SYM=$($NM "$KO" 2>/dev/null | awk '$3=="update_ddl_hit_history"{print $1; exit}')
if [ -n "${SYM:-}" ]; then
	ADDR=$((16#$SYM))
	echo "== disassembling symbol at 0x$SYM"
	$OBJDUMP -d --no-show-raw-insn --start-address=$ADDR --stop-address=$((ADDR+0x1a0)) "$KO" | tee "$OUT/ddl.txt"
else
	echo "== symbol table stripped, using runtime addresses"
	command -v adb >/dev/null || { echo "need adb for runtime offsets"; exit 1; }
	RT=$(adb shell su -c "grep -w update_ddl_hit_history /proc/kallsyms | cut -d' ' -f1" | tr -d '\r')
	TXT=$(adb shell su -c "cat /sys/module/$NAME/sections/.text" | tr -d '\r')
	[ -n "$RT" ] && [ -n "$TXT" ] || { echo "cannot read kallsyms/sections"; exit 1; }
	OFF=$((16#$RT - 16#$TXT))
	echo "== function offset in .text: 0x$(printf %x $OFF)"
	$OBJDUMP -d -j .text --no-show-raw-insn --start-address=$OFF --stop-address=$((OFF+0x1a0)) "$KO" | tee "$OUT/ddl.txt"
fi

cat <<'EOF'

== what to look for ==
1. index scaling right before the load/store:
     add xN, xBase, wIdx, lsl #5   -> entry stride 32 bytes
     lsl #4 -> 16, lsl #3 -> 8, umaddl with #24 -> 24
2. a bound compare against the index:
     cmp wIdx, #0x8000   (32768 = PID_MAX_DEFAULT)
     cmp wIdx, #0x400000 (4194304 = PID_MAX_LIMIT)
3. the store that faults at +0x144:
     str/strb to [xN, #imm]  -> imm is the field offset inside one entry
EOF

#!/bin/bash
# Runs inside "unshare -r -m" with /opt/ddk bind-mounted. Called by build-nodocker.sh.
# env: REPO, DDK_R, KMI
set -euo pipefail
: "${REPO:?}"; : "${KMI:?}"

export PATH="$REPO/.bin:/opt/ddk/clang/clang-r536225/bin:/usr/local/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$REPO/.libs"
export ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-
export KDIR="/opt/ddk/kdir/$KMI"

mkdir -p /tmp/b
mount -t tmpfs -o size=4G tmpfs /tmp/b

echo "== droid_lkm (4 modules)"
cp -a "$REPO/build/droid_lkm" /tmp/b/
cd /tmp/b/droid_lkm
make VER="$KMI" clean >/dev/null 2>&1 || true
make VER="$KMI"
mkdir -p "$REPO/build/out/$KMI"
cp -a "out/$KMI"/*.ko "$REPO/build/out/$KMI/"

echo "== net modules"
for m in net_macvlan net_ip6nat; do
	cp -a "$REPO/src/$m" /tmp/b/
	make -C "$KDIR" M="/tmp/b/$m" clean >/dev/null 2>&1 || true
	make -C "$KDIR" M="/tmp/b/$m" modules
	cp -a "/tmp/b/$m"/*.ko "$REPO/build/out/$KMI/"
done

echo "== artifacts"
ls -l "$REPO/build/out/$KMI"

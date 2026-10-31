#!/bin/bash
# Build with Docker using the DDK image.
#   scripts/build-docker.sh [kmi]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KMI=${1:-android16-6.12}
IMG=${DDK_IMAGE:-docker.cnb.cool/ylarod/ddk/ddk-min:$KMI}
OUT="$REPO/build/out/$KMI"
mkdir -p "$OUT"

echo "== droid_lkm"
docker run --rm -e KDIR="/opt/ddk/kdir/$KMI" \
	-e DROID_LKM_LAYOUT_FALLBACK -e DROID_LKM_LAYOUT_FORCE_BUILD \
	-e DROID_LKM_LAYOUT_MANUAL -e DROID_LKM_LAYOUT_TEST_BUILD_SHIFT \
	-v "$REPO/src/droid_lkm":/src -w /src "$IMG" \
	sh -c 'make VER="$1" clean >/dev/null 2>&1; make VER="$1"' sh "$KMI"
cp -a "$REPO/src/droid_lkm/out/$KMI"/*.ko "$OUT/"

echo "== net modules"
for m in net_macvlan net_ip6nat; do
	docker run --rm -e KDIR="/opt/ddk/kdir/$KMI" -v "$REPO/src/$m":/src -w /src "$IMG" \
		sh -c 'make -C "$KDIR" M=/src clean >/dev/null 2>&1; make -C "$KDIR" M=/src modules'
	cp -a "$REPO/src/$m"/*.ko "$OUT/"
done

ls -l "$OUT"

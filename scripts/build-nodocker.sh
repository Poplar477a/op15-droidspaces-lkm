#!/bin/bash
# Build without Docker, using an extracted Android DDK rootfs.
#   DDK_ROOT=/path/to/ddk/root scripts/build-nodocker.sh [kmi]
# DDK_ROOT must contain opt/ddk/kdir/<kmi> and opt/ddk/clang/clang-r536225.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KMI=${1:-android16-6.12}
DDK_R=${DDK_ROOT:-$REPO/../ddk/root}

[ -d "$DDK_R/opt/ddk/kdir/$KMI" ] || {
	echo "missing $DDK_R/opt/ddk/kdir/$KMI (set DDK_ROOT to the extracted image root)"; exit 1; }
[ -d "$REPO/src/droid_lkm" ] || { echo "missing src/droid_lkm"; exit 1; }

mkdir -p "$REPO/.libs" "$REPO/.bin" "$REPO/build/out/$KMI"

# host glibc usually lacks libdw; give gendwarfksyms/pahole the image copies only
for l in libdw.so.1 libelf.so.1 libzstd.so.1 liblzma.so.5 libbz2.so.1.0 libz.so.1; do
	[ -e "$DDK_R/usr/lib/x86_64-linux-gnu/$l" ] && \
		ln -sf "$DDK_R/usr/lib/x86_64-linux-gnu/$l" "$REPO/.libs/$l"
done
printf '#!/bin/sh\nexec %s/usr/bin/pahole "$@"\n' "$DDK_R" > "$REPO/.bin/pahole"
chmod 0755 "$REPO/.bin/pahole"

rm -rf "$REPO/build/droid_lkm"
cp -a "$REPO/src/droid_lkm" "$REPO/build/droid_lkm"

REPO="$REPO" KMI="$KMI" DDK_R="$DDK_R" unshare -r -m --propagation private bash -c \
	'mount -t tmpfs tmpfs /opt && mkdir -p /opt/ddk && mount --bind "$DDK_R/opt/ddk" /opt/ddk && exec bash "$REPO/scripts/build-inner.sh"'

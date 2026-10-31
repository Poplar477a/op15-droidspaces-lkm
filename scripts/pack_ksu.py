#!/usr/bin/env python3
"""Pack a KernelSU/Magisk module directory into a zip without the zip(1) tool.

usage: pack_ksu.py <src-dir> <out.zip>
Normalises permissions: *.sh and anything originally executable -> 0755,
everything else -> 0644. KernelSU needs update-binary/post-fs-data.sh executable.
"""
import os
import stat
import sys
import zipfile


def main(src: str, out: str) -> int:
    src = os.path.abspath(src)
    out = os.path.abspath(out)
    if not os.path.isdir(src):
        print("no such directory:", src, file=sys.stderr)
        return 1
    tmp = out + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(src):
            dirs.sort()
            rel_root = os.path.relpath(root, src)
            if rel_root != ".":
                zi = zipfile.ZipInfo(rel_root + "/")
                zi.external_attr = (stat.S_IFDIR | 0o755) << 16
                z.writestr(zi, b"")
            for name in sorted(files):
                path = os.path.join(root, name)
                rel = os.path.relpath(path, src)
                st = os.lstat(path)
                if stat.S_ISLNK(st.st_mode):
                    zi = zipfile.ZipInfo(rel)
                    zi.external_attr = (stat.S_IFLNK | 0o777) << 16
                    z.writestr(zi, os.readlink(path))
                    continue
                if name.endswith(".sh") or name == "update-binary":
                    mode = 0o755
                else:
                    mode = 0o644
                zi = zipfile.ZipInfo(rel)
                zi.external_attr = (stat.S_IFREG | mode) << 16
                zi.compress_type = zipfile.ZIP_DEFLATED
                with open(path, "rb") as fh:
                    z.writestr(zi, fh.read())
    os.replace(tmp, out)
    print("->", out)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
